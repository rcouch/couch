-module(couch_event).
-export([subscribe/1, notify/2]).

-record(await_opts, {timeout,
                     heartbeat=false,
                     continuous=false}).

subscribe(EventType) ->
    gproc:reg(key_for_event(EventType)).

notify(EventType, Msg) ->
    gproc:send(key_for_event(EventType), Msg).

await(EventType, MFA) -<>
    await(EventType, MFA, [{timeout, infinity}, {heartbeat, false},
                           {continuous, false}]).

await(EventType, F) ->
    await(Eventype, {undefined, F}, []).

await(

await(EventType, Mod, Fun, Acc, Opts) ->
    _ = subscribe(EventType),
    receive
        {key_for_event(EventType), Event} ->
            do_apply(MFQ


key_for_event(EventType) ->
    {p, l, {?MODULE, EventType}}.
