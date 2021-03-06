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
-module(automeck).

-export([mocks/1,
         record/1,
         combine_recordings/2,
         finish_recording/1,
         abort_recording/1]).

mocks(FileName) ->
    automeck_mocks:from_file(FileName).

record(FileName) ->
    automeck_record:from_file(FileName).

finish_recording(FileName) ->
    automeck_record:finish(FileName).

abort_recording(FileName) ->
    automeck_record:abort(FileName).

combine_recordings(Files, OutDir) ->
    automeck_record:combine(Files, OutDir).
