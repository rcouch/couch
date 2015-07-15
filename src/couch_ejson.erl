-module(couch_ejson).

-include("couch_db.hrl").

decode(Bin) ->
    ?JSON_DECODE(Bin).

encode(Json) ->
    ?JSON_ENCODE(Json).
