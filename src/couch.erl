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

-module(couch).

-export([version/0]).
-export([start/0,  stop/0, restart/0, reload/0]).

-export([create_db/1, create_db/2,
         open_db/1, open_db/2,
         open_or_create_db/1, open_or_create_db/2,
         delete_db/1,
         all_databases/0, all_databases/2,
         database_info/1]).

-include("couch_db.hrl").

-record(cdb, {name, options}).

-type dbname() :: string() | binary().
-type db() :: #cdb{}.
-type db_options() :: [sys_db |
                       {user_ctx, #user_ctx{}} |
                       {before_doc_update, fun() | nil} |
                       {after_doc_update, fun() | nil}].
-type db_info() :: list().

-export_types([dbname/0,
               db/0,
               db_options/0,
               db_info/0]).

%% @doc return the couch application version
version() ->
    case application:get_key(couch, vsn) of
        {ok, FullVersion} ->
            hd(string:tokens(FullVersion, "-"));
        _ ->
            "0.0.0"
    end.


%% @doc start the couchdb application. mostly for debug purpose.
start() ->
    couch_util:start_app_deps(couch),
    application:start(couch).


%% @doc stop the couchdb application. mostly for debug purpose.
stop() ->
    application:stop(couch).

%% @restart the couch application
restart() ->
    case stop() of
    ok ->
        start();
    {error, {not_started,couch}} ->
        start();
    {error, Reason} ->
        {error, Reason}
    end.

%% reload the couch configuration
reload() ->
    case supervisor:terminate_child(couch_sup, couch_config) of
    ok ->
        supervisor:restart_child(couch_sup, couch_config);
    {error, Reason} ->
        {error, Reason}
    end.

%% --------------------
%% Databases operations
%% --------------------

%% @doc create a database
-spec create_db(dbname()) -> {ok, db()} | {error, term()}.
create_db(DbName) ->
    create_db(DbName, []).

%% @doc create a database
-spec create_db(dbname(), db_options()) -> {ok, db()} | {error, term()}.
create_db(DbName0, Options0) ->
    DbName = dbname(DbName0),
    Options = db_options(Options0),
    case couch_server:create(DbName, Options) of
        {ok, Db} ->
            ok = couch_db:close(Db),
            {ok, #cdb{name=DbName, options=Options}};
        Error ->
            Error
    end.

%% @doc open a database
-spec open_db(dbname()) -> {ok, db()} | {error, term()}.
open_db(DbName) ->
    open_db(DbName, []).

%% @doc open a database
-spec open_db(dbname(), db_options()) -> {ok, db()} | {error, term()}.
open_db(DbName0, Options0) ->
    DbName = dbname(DbName0),
    Options = db_options(Options0),
    case couch_server:open(DbName, Options) of
        {ok, Db} ->
            ok = couch_db:close(Db),
            {ok, #cdb{name=DbName, options=Options}};
        Error ->
            Error
    end.


%% @doc open or create a database if it doesn't exist
-spec open_or_create_db(dbname()) -> {ok, db()} | {error, term()}.
open_or_create_db(DbName) ->
    open_or_create_db(DbName, []).

%% @doc open or create a database if it doesn't exist
-spec open_or_create_db(dbname(), db_options())
    -> {ok, db()} | {error, term()}.
open_or_create_db(DbName, Options) ->
    case create_db(DbName, Options) of
        {ok, Db} -> {ok, Db};
        {error, file_exists} -> open_db(DbName, Options);
        Error -> Error
    end.

%% @doc delete a database
-spec delete_db(db() | dbname()) -> ok | {error, term()}.
delete_db(#cdb{name=DbName}) ->
    delete_db(DbName);
delete_db(DbName) ->
    case couch_server:delete(dbname(DbName), []) of
        ok -> ok;
        Error -> {error, Error}
    end.

%% @doc list all databases
-spec all_databases() -> [dbname()] | {error, term()}.
all_databases() ->
    couch_server:all_databases().

%% @doc fold all datbases
-spec all_databases(Fun::fun(), AccIn::any()) -> Acc::any()| {error, term()}.
all_databases(Fun, Acc0) ->
    couch_server:all_databases(Fun, Acc0).


%% @doc get database info
-spec database_info(db()) -> {ok, db_info()} | {error, term()}.
database_info(Db) ->
    with_db(Db, fun(Db0) ->
                {ok, Info} = couch_db:get_db_info(Db0),
                {ok, {Info}}
        end).


%% @private
dbname(DbName) when is_list(DbName) ->
    list_to_binary(DbName);
dbname(DbName) when is_binary(DbName) ->
    DbName;
dbname(DbName) ->
    erlang:error({illegal_database_name, DbName}).


with_db(#cdb{name=DbName, options=Options}, Fun) ->
    case couch_server:open(DbName, Options) of
        {ok, Db} ->
            try
                Fun(Db)
            after
                    catch couch_db:close(Db)
                end;
        Error ->
            Error
        end.

db_options(Options) ->
    case lists:member(user_ctx, Options) of
        true -> Options;
        false ->
            [{user_ctx, #user_ctx{roles=[<<"_admin">>]}} | Options]
    end.
