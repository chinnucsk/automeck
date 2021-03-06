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
-module(automeck_mocks).

-export([from_list/1,
         from_file/1]).

from_file(File) ->
    {ok, Descs} = file:consult(File),
    from_list(Descs).

from_list([{mock, Descs0}]) ->
    Descs1 = lists:keysort(1, Descs0),
    Descs2 = sort_by_arity(Descs1, []),
    Descs3 = generate_funs(Descs2, []),
    generate_mocks(Descs3).

sort_by_arity([], Accum) ->
    lists:reverse(Accum);
sort_by_arity([{Mod, Name, Impls0}|T], Accum) when length(Impls0) > 1 ->
    F = fun({FArgs, _}, {SArgs, _}) ->
                length(FArgs) =< length(SArgs) end,
    Impls = lists:sort(F, Impls0),
    sort_by_arity(T, [{Mod, Name, Impls}|Accum]);
sort_by_arity([H|T], Accum) ->
    sort_by_arity(T, [H|Accum]).

generate_funs([], Accum) ->
    lists:reverse(Accum);
generate_funs([{Mod, Name, [{Args, Return}]}|T], Accum) ->
    Code = build_fun(Args, Return),
    generate_funs(T, [{Mod, Name, [Code]}|Accum]);
generate_funs([{Mod, Name, Impls}|T], Accum) ->
    Heads = separate_fun_heads(Impls),
    Code = [generate_fun_heads(H) || H <- Heads],
    generate_funs(T, [{Mod, Name, Code}|Accum]).

build_fun(Args, Return) ->
    build_fun(Args, Return, "fun", " end.").

build_fun(Args, Return, Prefix, Suffix) ->
    ArgFmt = format_string(args, Args),
    ReturnFmt = format_string(return, Return),
    Fmt = prefix(Prefix) ++ "(" ++ ArgFmt ++ ") -> " ++ ReturnFmt ++
           suffix(Suffix),
    Code =  lists:flatten(io_lib:format(Fmt, Args ++ [Return])),
    re:replace(Code, "'_'", "_", [global, {return, list}]).

prefix(none) ->
    "";
prefix(Prefix) ->
    Prefix.

suffix(none) ->
    "";
suffix(Suffix) ->
    Suffix.

format_string(args, []) ->
    "";
format_string(args, Args) ->
    Fmt = lists:flatten(["~p," || _ <- lists:seq(1, length(Args))]),
    lists:reverse(tl(lists:reverse(Fmt)));
format_string(return, _Return) ->
    "~p".

separate_fun_heads([]) ->
    [];
separate_fun_heads([{Args, _}|_]=Impls) ->
    separate_fun_heads(length(Args), Impls, [], []).

generate_fun_heads(Heads) ->
    generate_fun_heads(Heads, []).

generate_fun_heads([{Args, Return}|T], Accum) when length(T) == 0 ->
    case length(Accum) == 0 of
        true ->
            build_fun(Args, Return, "fun", " end.\n");
        false ->
            Accum ++ build_fun(Args, Return, none, " end.\n")
    end;
generate_fun_heads([{Args, Return}|T], Accum) ->
    Code = case length(Accum) == 0 of
               true ->
                   build_fun(Args, Return, "fun", ";\n");
               false ->
                   build_fun(Args, Return, none, ";\n")
           end,
    generate_fun_heads(T, Accum ++ Code).

separate_fun_heads(_Arity, [], Current, All) ->
    lists:reverse([Current|All]);
separate_fun_heads(Arity, [{Args, _}=H|T], Current, All) when length(Args) == Arity ->
    separate_fun_heads(Arity, T, [H|Current], All);
separate_fun_heads(_Arity, [{Args, _}=H|T], Current, All) ->
    separate_fun_heads(length(Args), T, [H], [Current|All]).

generate_mocks(Mocks) ->
    generate_mocks(Mocks, []).

generate_mocks([], Accum) ->
    lists:usort(Accum);
generate_mocks([{Mod, Name, Codes}|T], Accum) ->
    case catch meck:new(Mod) of
        ok ->
            ok;
        {'EXIT', {{already_started, _}, _}} ->
            ok
    end,
    [meck:expect(Mod, Name, automeck_compile:compile(Code)) || Code <- Codes],
    generate_mocks(T, [Mod|Accum]).
