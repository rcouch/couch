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
         database_info/1,
         ensure_full_commit/1, ensure_full_commit/2]).


-export([get/2, get/3,
         stream_doc/1]).

-include("couch_db.hrl").

-record(cdb, {name, options}).

-type dbname() :: string() | binary().
-type db() :: #cdb{}.
-type db_options() :: [sys_db |
                       {user_ctx, #user_ctx{}} |
                       {before_doc_update, fun() | nil} |
                       {after_doc_update, fun() | nil}].
-type db_info() :: list().

-export_type([dbname/0,
               db/0,
               db_options/0,
               db_info/0]).


-type docid() :: binary().
-type rev() :: binary().
-type update_type() :: replicated_changes | interactive_edit.
-type doc_options() :: [attachments |
                        {revs, list()} |
                        local_seq |
                        revs_info |
                        deleted_conflicts |
                        rev |
                        {open_revs, all | list()} |
                        latest |
                        {atts_since, list()} |
                        {update_type, update_type()} |
                        att_encoding_info |
                        stream |
                        {timeout, infinity | integer()}].

-type ejson_array() :: [ejson_term()].
-type ejson_object() :: {[{ejson_key(), ejson_term()}]}.

-type ejson_key() :: binary() | atom().

-type ejson_term() :: ejson_array()
    | ejson_object()
    | ejson_string()
    | ejson_number()
    | true | false | null.

-type ejson_string() :: binary().

-type ejson_number() :: float() | integer().

-type doc() :: ejson_object().

-opaque next() :: function().

-export_type([update_type/0,
              doc_options/0,
              docid/0,
              rev/0,
              doc/0,
              next/0]).

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

%% @doc ensure full commit of docs
-spec ensure_full_commit(Db::db())
    -> {ok, StartTime::integer()} | {error, term()}.
ensure_full_commit(Db) ->
    ensure_full_commit(Db, undefined).

%% @doc ensure full commit of docs
-spec ensure_full_commit(Db::db(), RequiredSeq::integer())
    -> {ok, StartTime::integer()} | {error, term()}.
ensure_full_commit(Db, RequiredSeq) ->
    with_db(Db, fun(Db0) ->
                UpdateSeq = couch_db:get_update_seq(Db0),
                CommittedSeq = couch_db:get_committed_update_seq(Db0),
                case RequiredSeq of
                    undefined ->
                        couch_db:ensure_full_commit(Db0);
                    _ when RequiredSeq > UpdateSeq ->
                        {error, seq_ahead};
                    _ when RequiredSeq > CommittedSeq ->
                        couch_db:ensure_full_commit(Db0);
                    _ ->
                        {ok, Db0#db.instance_start_time}
                end
        end).

%% @doc get a document from the database
-spec get(Db::db(), docid())
    ->  {ok, doc()} | {ok, [{ok, doc()} | {missing, rev()}]}
    | {error, term()}.
get(Db, DocId) ->
    get(Db, DocId, []).

%% @doc get a document from the database
-spec get(Db::db(), docid(), doc_options())
    ->  {ok, doc()} | {ok, [{ok, doc()} | {missing, rev()}]} |
    {ok, {stream, next()}} |
    {error, term()}.
get(Db, DocId, Options0) ->
    Options = case couch_util:get_value(atts_since, Options0) of
        undefined -> Options0;
        RevList when is_list(RevList) ->
            [attachments | Options0]
    end,

    Revs = couch_util:get_value(open_revs, Options, []),
    Rev = couch_util:get_value(rev, Options, nil),
    Stream = lists:member(stream, Options),
    Attachments = lists:member(attachments, Options),

    case Revs of
        [] ->
            case couch_doc_open(Db, DocId, Rev, Options) of
                {ok, #doc{atts=[]}=Doc} ->
                    {ok, couch_doc:to_json_obj(Doc, Options)};
                {ok, Doc} when Stream /= true, Attachments /= true ->
                    {ok, couch_doc:to_json_obj(Doc, Options)};
                {ok, Doc} ->
                    Options1 = [attachments, follows, att_encoding_info
                                | Options],
                    {ok, {stream, fun() ->
                                    stream_docs([Doc], DocId, Options1)
                            end}};
                Error ->
                    Error
            end;
        _ ->
            case open_doc_revs(Db, DocId, Revs, Options) of
                {ok, Results} when Stream /= true ->
                    Results2 = lists:foldl(fun
                                ({ok, Doc}, Acc) ->
                                    JsonDoc = couch_doc:to_json_obj(
                                            Doc, Options),
                                    [{ok, JsonDoc} | Acc];
                                ({{not_found, missing}, RevId}, Acc) ->
                                    RevStr = couch_doc:rev_to_str(RevId),
                                    [{missing, RevStr} | Acc]
                            end, [], Results),
                    {ok, lists:reverse(Results2)};
                {ok, Results} ->
                    Options1 = [attachments, follows, att_encoding_info
                                | Options],
                    {ok, {stream, fun() ->
                                    stream_docs(Results, DocId, Options1)
                            end}};
                Error ->
                    Error
            end
    end.


%% @doc stream document. Function to use when the stream option is used
%% for a document.
-spec stream_doc(Next::next()) ->
    {doc, DocId::docid(), Doc::doc(), Next2::next()} |
    {att, Name::binary(), AttInfo::list(), Next2::next()} |
    {att_body, Name::binary(), Next2::next()} |
    {att_eof, Name::binary(), Next2::next()} |
    {doc_eof, DocId::docid()}.
stream_doc(Next) when is_function(Next) ->
    Next().


%% stream doc functions

stream_docs([], DocId, _Options) ->
    {doc_eof, DocId};
stream_docs([{{not_found, missing}, RevId} | Rest], DocId, Options) ->
    RevStr = couch_doc:rev_to_str(RevId),
    {missing, RevStr, fun() ->
                stream_docs(Rest, DocId, Options)
        end};
stream_docs([{ok, #doc{atts=Atts}=Doc} | Rest], DocId, Options) ->
    JsonDoc = couch_doc:to_json_obj(Doc, Options),
    {doc, DocId, JsonDoc, fun() ->
                stream_attachments(Atts, Rest, DocId, Options)
        end}.


stream_attachments([], [], DocId, _Options) ->
    {doc_eof, DocId};
stream_attachments([], Docs, DocId, Options) ->
    stream_docs(Docs, DocId, Options);
stream_attachments([Att |Rest], Docs, DocId, Options) ->
    #att{
        name=Name,
        att_len=AttLen,
        disk_len=DiskLen,
        type=Type,
        encoding=Encoding
    } = Att,

    AttInfo = [{name, Name},
               {att_len, AttLen},
               {disk_len, DiskLen},
               {type, Type},
               {encoding, Encoding}],

    case lists:member(stream_att_infos, Options) of
        true ->
            {att, Name, AttInfo, fun() ->
                        stream_attachments(Rest, Docs, DocId, Options)
                end};
        false ->
            {att, Name, AttInfo, fun() ->
                        stream_attachment(Att, Rest, Docs, DocId, Options)
                end}
    end.

stream_attachment({att_eof, Name}, Atts, Docs, DocId, Options) ->
    {att_eof, Name, fun() ->
                stream_attachments(Atts, Docs, DocId, Options)
        end};
stream_attachment(#att{name=Name, data=Bin}, Atts, Docs, DocId, Options)
        when is_binary(Bin) ->
    {att_chunk, Name, Bin, fun() ->
                stream_attachment({att_eof, Name}, Atts, Docs, DocId, Options)
        end};
stream_attachment(#att{name=Name}=Att, Atts, Docs, DocId, Options) ->
    StreamType = proplists:get_value(stream, Options, false),
    Stream = couch_stream:init_stream(Att, StreamType),
    stream_attachment1(Name, Stream, Atts, Docs, DocId, Options).

stream_attachment1(Name, Stream, Atts, Docs, DocId, Options) ->
    case couch_stream:stream(Stream) of
        {more, Bin, Stream2} ->
            {att_chunk, Name, Bin, fun() ->
                        stream_attachment1(Name, Stream2, Atts, Docs,
                                           DocId, Options)
                end};
        eof ->
            {att_eof, Name, fun() ->
                        stream_attachments(Atts, Docs, DocId, Options)
                end};
        Error ->
            Error
    end.

%% @private
dbname(DbName) when is_list(DbName) ->
    list_to_binary(DbName);
dbname(DbName) when is_binary(DbName) ->
    DbName;
dbname(DbName) ->
    erlang:error({illegal_database_name, DbName}).

open_doc_revs(Db0, DocId, Revs, Options) ->
    with_db(Db0, fun(Db) ->
                couch_db:open_doc_revs(Db, DocId, Revs, Options)
        end).

couch_doc_open(Db0, DocId, Rev, Options) ->
    with_db(Db0, fun(Db) ->
                case Rev of
                    nil -> % open most recent rev
                        case couch_db:open_doc(Db, DocId, Options) of
                            {ok, Doc} ->
                                {ok, Doc};
                            Error ->
                                {error, Error}
                        end;
                    _ -> % open a specific rev (deletions come back as stubs)
                        case couch_db:open_doc_revs(Db, DocId, [Rev],
                                                    Options) of
                            {ok, [{ok, Doc}]} ->
                                {ok, Doc};
                            {ok, [{{not_found, missing}, Rev}]} ->
                                {error, not_found};
                            {ok, [Else]} ->
                                {error, Else}
                        end
                end
        end).

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
