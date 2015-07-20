% Licensed under the Apache License, Version 2.0 (the "License"); you may not
% use this file except in compliance with the License. You may obtain a copy of
% the License at
%
%   http://www.apache.org/licenses/LICENSE-2.0
%
% Unless required by applicable law or agreed to in writing, software
% distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
% WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
% License for the specific language governing permissions and limitations under
% the License.

-module(couch_hooks).

-export([add/4, add/5,
         remove/4, remove/5,
         run/2, run/3,
         run_fold/3, run_fold/4,
         run_until_ok/2, run_until_ok/3]).

-export([init_hooks/0]).

-define(HOOKS, couch_hooks).

add(Hook, Module, Fun, Prio) ->
    Key = {{g, Hook}, Prio, {Module, Fun}},
    Val = {Module, Fun},
    ets:insert_new(?HOOKS, {Key, Val}).

add(Hook, DbName, Module, Fun, Prio) ->
    Key = {{db, Hook, DbName}, Prio, {Module, Fun}},
    Val = {Module, Fun},
    ets:insert_new(?HOOKS, {Key, Val}).

remove(Hook, Module, Fun, Prio) ->
    Key = {{g, Hook}, Prio, {Module, Fun}},
    ets:delete(?HOOKS, Key).

remove(Hook, DbName, Module, Fun, Prio) ->
    Key = {{db, Hook, DbName}, Prio, {Module, Fun}},
    ets:delete(?HOOKS, Key).


run(Hook, Args) ->
    lists:foreach(fun({M, F}) ->
                          erlang:apply(M, F, Args)
                  end, ets:select(?HOOKS, [{{{{g, Hook}, '_', '_'}, $1},
                                            [], ['$1']}])).

run(Hook, DbName, Args) ->
    lists:foreach(fun({M, F}) ->
                          erlang:apply(M, F, Args)
                  end, ets:select(?HOOKS,
                                  [{{{{db, Hook, '$1'}, '_', '_'}, '$2'},
                                    [{'orelse',
                                      {'==', '$1', DbName},
                                      {'==', '$1', all}}],
                                    ['$2']}])).


run_fold(Hook, Args, Acc) ->
    lists:fold(fun({M, F}, Acc1) ->
                          erlang:apply(M, F, Args ++ [Acc1])
                  end, Acc, ets:select(?HOOKS, [{{{{g, Hook}, '_', '_'}, $1},
                                                 [], ['$1']}])).

run_fold(Hook, DbName, Args, Acc) ->
    lists:fold(fun({M, F}, Acc1) ->
                          erlang:apply(M, F, Args ++ [Acc1])
                  end, Acc, ets:select(?HOOKS,
                                       [{{{{db, Hook, '$1'}, '_', '_'}, '$2'},
                                         [{'orelse',
                                           {'==', '$1', DbName},
                                           {'==', '$1', all}}],
                                         ['$2']}])).

run_until_ok(Hook, Args) ->
    Hooks = ets:select(?HOOKS, [{{{{g, Hook}, '_', '_'}, $1}, [], ['$1']}]),
    loop_until_ok(Hooks, Args).


run_until_ok(Hook, DbName, Args) ->
    Hooks = ets:select(?HOOKS, [{{{{db, Hook, '$1'}, '_', '_'}, '$2'},
                                 [{'orelse',
                                   {'==', '$1', DbName},
                                   {'==', '$1', all}}],
                                 ['$2']}]),
    loop_until_ok(Hooks, Args).


loop_until_ok([], _Args) ->
    error;
loop_until_ok([{M, F} | Rest], Args) ->
    case erlang:apply(M, F, Args) of
        ok -> ok;
        _ -> run_until_ok(Rest, Args)
    end.


init_hooks() ->
    case ets:info(?HOOKS, name) of
        undefined ->
            ets:new(?HOOKS, [ordered_set, public, named_table,
                             {read_concurrency, true},
                             {write_concurrency, true}]);
        _ ->
            ok
    end.
