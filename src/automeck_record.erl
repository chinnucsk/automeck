%% Copyright (c) 2011 Opscode, Inc.  All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
-module(automeck_record).

-define(ARG_PROTOS,  [{0,  ""},
                      {1,  "A"},
                      {2,  "A,B"},
                      {3,  "A,B,C"},
                      {4,  "A,B,C,D"},
                      {5,  "A,B,C,D,E"},
                      {6,  "A,B,C,D,E,F"},
                      {7,  "A,B,C,D,E,F,G"},
                      {8,  "A,B,C,D,E,F,G,H"},
                      {9,  "A,B,C,D,E,F,G,H,I"},
                      {10, "A,B,C,D,E,F,G,H,I,J"}]).

-export([reset_session_ids/0,
	 from_file/2,
         from_list/2,
         log_result/5,
         finish/1,
         abort/1,
         combine/2]).



-record(automeck_state, {
	  session_name = none,
	  session_id,
	  mock_name = "mocks",
	  filename,
	  output_path,
	  opts
	 }).
		
-include_lib("eunit/include/eunit.hrl").

reset_session_ids() ->
    ets:delete(automeck_sessions).

get_unique_session_id(Session) ->
    case ets:info(automeck_sessions) of
	undefined ->
	    ets:new(automeck_sessions, [set, public, named_table]);
	_ -> ok
    end, 
    SessionId = 
	case ets:lookup(automeck_sessions, Session) of
	    [] -> 0;
	    [{Session, Id}] -> Id
	end,
    ets:insert(automeck_sessions, {Session, SessionId+1}),
    SessionId.

parse_opts(OutputPath, Opts) ->
    SessionName = proplists:get_value(session_name, Opts, none),
    MockName = proplists:get_value(mock_name, Opts, "mocks"),
    SessionId = get_unique_session_id(SessionName),
    OutputPath2 = 
	case proplists:get_value(output_path, Opts) of
	    undefined -> OutputPath;
	    Path -> Path
	end,
    #automeck_state{session_name = SessionName,
		    session_id = SessionId,
		    mock_name = MockName,
		    output_path = OutputPath2,
		    opts = Opts}.

from_file(Path, Opts) ->
    {ok, Descs} = file:consult(Path),
    from_list(Descs, Opts).

from_list([{record, OutputPath, Descs0}], Opts) ->
    Descs = [{Module, Exports, first} || {Module, Exports} <- Descs0],
    State = parse_opts(OutputPath, Opts),
    FileName = output_file(OutputPath, State),   
    ok = filelib:ensure_dir(FileName),
    file:delete(FileName),
    ok = insert_interceptors(FileName, Descs),
    {ok, State#automeck_state{filename = FileName}}.

abort(#automeck_state{filename=FileName}) ->
    meck:unload(),
    file:delete(FileName),
    ok.

finish(#automeck_state{filename=FileName} = State) ->
    meck:unload(),
    {ok, Calls} = file:consult(FileName),
    MockConfig = generate_mock_config(Calls),
    save_mock_config(State#automeck_state.output_path, MockConfig, State).

combine(Files, OutDir) ->
    F = fun(File) -> {ok, Calls} = file:consult(File),
                     generate_mock_config(Calls, orddict:new()) end,
    Configs = [F(File) || File <- Files],
    MockConfig = {mock, [{Mod, Name, Impls} || {{Mod, Name}, Impls} <- merge_configs(Configs)]},
    save_mock_config(OutDir, MockConfig, #automeck_state{}).

insert_interceptors(_OutputFile, []) ->
    ok;
insert_interceptors(OutputFile, [{Module, all, first}|T]) ->
    Exports = Module:module_info(exports),
    insert_interceptors(OutputFile, [{Module, Exports, first}|T]);
insert_interceptors(OutputFile, [{Module, Exports, first}|T]) ->
    {module, Module} = code:ensure_loaded(Module),
    meck:new(Module),
    insert_interceptors(OutputFile, [{Module, Exports}|T]);
insert_interceptors(OutputFile, [{Module, Exports}|T]) ->
    OrigModule = list_to_atom(atom_to_list(Module) ++ "_meck_original"),
    AllExports = sets:from_list(OrigModule:module_info(exports)),
    PassthruExports = sets:to_list(sets:subtract(AllExports, sets:from_list(Exports))),
    [build_interceptor(OutputFile, Module, OrigModule, Name, Arity) || {Name, Arity} <- Exports,
                                                                       Name /= module_info],
    [build_passthru(Module, Name, Arity) || {Name, Arity} <- PassthruExports,
                                            Name /= module_info],
    insert_interceptors(OutputFile, T).

build_interceptor(OutputFile, Module, OrigModule, Name, Arity) ->
    Args = proplists:get_value(Arity, ?ARG_PROTOS),
    Fmt = "fun(~s) -> R = ~p:~p(~s), io:fwrite(user, <<\"~~s \">>, [~p]), automeck_record:log_result(~p, ~p, ~p, ~s, R), R end.",
    Code = lists:flatten(io_lib:format(Fmt, [Args, OrigModule, Name, Args, Name, OutputFile,
                                             Module, Name, "[" ++ Args ++ "]"])),
    meck:expect(Module, Name, automeck_compile:compile(Code)).

build_passthru(Module, Name, Arity) ->
    Args = proplists:get_value(Arity, ?ARG_PROTOS),
    Fmt = "fun(~s) -> meck:passthrough([~s]) end.",
    Code = lists:flatten(io_lib:format(Fmt, [Args, Args])),
    meck:expect(Module, Name, automeck_compile:compile(Code)).

log_result(OutputFile, Module, Fun, Args, Result) ->
    file:write_file(OutputFile, io_lib:format("{~p, ~p, [{~p, ~p}]}.~n",
                                            [Module, Fun, Args, Result]),
                    [append]).


generate_filename(BaseName, Ext,
		  #automeck_state{session_name=SessionName, 
				  session_id=SessionId} = State) ->
    FilenameParts = 
	case SessionName of
	    none -> [BaseName, Ext];
	    _ -> [BaseName, "_" , 
		  atom_to_list(SessionName), "_", integer_to_list(SessionId),
		  Ext]
	end,
    lists:flatten(FilenameParts).


output_file(OutputPath, #automeck_state{} = State) ->
    filename:join([OutputPath, 
		   generate_filename("automeck_record", ".session", State)]).

conf_file(OutputPath, #automeck_state{} = State) ->
    filename:join([OutputPath, 
		   generate_filename(State#automeck_state.mock_name, 
				     ".config", State)]).

generate_mock_config(Calls) ->
    Config0 = generate_mock_config(Calls, orddict:new()),
    {mock, [{Mod, Name, Impls} || {{Mod, Name}, Impls} <- orddict:to_list(Config0)]}.

generate_mock_config([], Config) ->
    Config;
generate_mock_config([{Module, Name, Impl}|T], Config) ->
    Key = {Module, Name},
    Config1 = case orddict:is_key(Key, Config) of
                  false ->
                      orddict:store(Key, Impl, Config);
                  true ->
                      Impls = orddict:fetch(Key, Config),
                      orddict:store(Key, lists:usort(Impl ++ Impls), Config)
              end,
    generate_mock_config(T, Config1).

save_mock_config(OutputDir, Config, State) ->
    OutputFile = conf_file(OutputDir, State),
    ok = file:write_file(OutputFile, io_lib:format("~p.~n", [Config])),
    {ok, OutputFile}.

merge_configs([Config]) ->
    Config;
merge_configs([F,S]) ->
    orddict:merge(fun detect_conflicts/3, F, S);
merge_configs([F,S|T]) ->
    F1 = orddict:merge(fun detect_conflicts/3, F, S),
    merge_configs([F1|T]).

detect_conflicts({Mod, Fun}, Impls1, Impls2) ->
    case is_conflicted(Mod, Fun, Impls1, Impls2) of
        false ->
            lists:usort(lists:flatten(Impls1 ++ Impls2));
        {true, {Mod, Fun, Args, Retvals}} ->
            error({conflicting_function_calls, Mod, Fun, Args, Retvals})
    end.

is_conflicted(_Mod, _Fun, [], _Impls2) ->
    false;
is_conflicted(Mod, Fun, [{Args, Retval}|T], Impls2) ->
    case proplists:get_value(Args, Impls2) of
        undefined ->
            is_conflicted(Mod, Fun, T, Impls2);
        Retval ->
            is_conflicted(Mod, Fun, T, Impls2);
        Other ->
            {true, {Mod, Fun, Args, [Retval, Other]}}
    end.
