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

-module(couch_ejson_doc).

-export([set_value/3, get_value/2, get_value/3,
         take_value/2, take_value/3,
         delete_value/2, extend/2, extend/3]).
-export([get_id/1, get_rev/1, get_idrev/1, is_saved/1]).

%% @doc get document id.
get_id(Doc) ->
    get_value(<<"_id">>, Doc).

%% @doc get document revision.
get_rev(Doc) ->
    get_value(<<"_rev">>, Doc).

%% @doc get  a tuple containing docucment id and revision.
get_idrev(Doc) ->
    DocId = get_value(<<"_id">>, Doc),
    DocRev = get_value(<<"_rev">>, Doc),
    {DocId, DocRev}.

%% @doc If document have been saved (revision is defined) return true,
%% else, return false.
is_saved(Doc) ->
    case get_value(<<"_rev">>, Doc) of
        undefined -> false;
        _ -> true
    end.

%% @doc set a value for a key in jsonobj. If key exists it will be updated.
set_value(Key, Value, JsonObj) when is_list(Key)->
    set_value(list_to_binary(Key), Value, JsonObj);
set_value(Key, Value, JsonObj) when is_binary(Key) ->
    {Props} = JsonObj,
    case proplists:is_defined(Key, Props) of
        true -> set_value1(Props, Key, Value, []);
        false-> {lists:reverse([{Key, Value}|lists:reverse(Props)])}
    end.

%% @doc Returns the value of a simple key/value property in json object
%% Equivalent to get_value(Key, JsonObj, undefined).
get_value(Key, JsonObj) ->
    get_value(Key, JsonObj, undefined).


%% @doc Returns the value of a simple key/value property in json object
%% function from erlang_couchdb
get_value(Key, JsonObj, Default) when is_list(Key) ->
    get_value(list_to_binary(Key), JsonObj, Default);
get_value(Key, JsonObj, Default) when is_binary(Key) ->
    {Props} = JsonObj,
    couch_util:get_value(Key, Props, Default).


%% @spec take_value(Key::key_val(), JsonObj::json_obj()) -> {term(), json_obj()}
%% @doc Returns the value of a simple key/value property in json object and deletes
%% it form json object
%% Equivalent to take_value(Key, JsonObj, undefined).
take_value(Key, JsonObj) ->
    take_value(Key, JsonObj, undefined).


%% @doc Returns the value of a simple key/value property in json object and deletes
%% it from json object
take_value(Key, JsonObj, Default) when is_list(Key) ->
    get_value(list_to_binary(Key), JsonObj, Default);
take_value(Key, JsonObj, Default) when is_binary(Key) ->
    {Props} = JsonObj,
    case lists:keytake(Key, 1, Props) of
        {value, {Key, Value}, Rest} ->
            {Value, {Rest}};
        false ->
            {Default, JsonObj}
    end.

%% @doc Deletes all entries associated with Key in json object.
delete_value(Key, JsonObj) when is_list(Key) ->
    delete_value(list_to_binary(Key), JsonObj);
delete_value(Key, JsonObj) when is_binary(Key) ->
    {Props} = JsonObj,
    Props1 = proplists:delete(Key, Props),
    {Props1}.

%% @doc extend a jsonobject by key, value
extend(Key, Value, JsonObj) ->
    extend({Key, Value}, JsonObj).


%% @doc extend a jsonobject by a property, list of property or another jsonobject
extend([], JsonObj) ->
    JsonObj;
extend({List}, JsonObj) when is_list(List)  ->
    extend(List, JsonObj);
extend([Prop|R], JsonObj)->
    NewObj = extend(Prop, JsonObj),
    extend(R, NewObj);
extend({Key, Value}, JsonObj) ->
    set_value(Key, Value, JsonObj).

%% @private
set_value1([], _Key, _Value, Acc) ->
    {lists:reverse(Acc)};
set_value1([{K, V}|T], Key, Value, Acc) ->
    Acc1 = if
        K =:= Key ->
            [{Key, Value}|Acc];
        true ->
            [{K, V}|Acc]
        end,
    set_value1(T, Key, Value, Acc1).
