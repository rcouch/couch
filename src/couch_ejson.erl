-module(couch_ejson).

-include("couch_db.hrl").

-export([decode/1, encode/1]).

decode(Bin) ->
    ?JSON_DECODE(Bin).

encode(Json) ->
    ?JSON_ENCODE(Json).
