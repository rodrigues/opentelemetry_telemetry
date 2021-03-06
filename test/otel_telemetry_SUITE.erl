-module(otel_telemetry_SUITE).

-compile(export_all).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").
-include_lib("opentelemetry_api/include/opentelemetry.hrl").
-include_lib("opentelemetry/include/ot_span.hrl").

all() -> [
          successful_span,
          exception_span
         ].

init_per_suite(Config) ->
    ok = application:load(opentelemetry_telemetry),
    ok = application:load(opentelemetry),
    application:set_env(opentelemetry, processors, [{ot_batch_processor, #{scheduled_delay_ms => 1}}]),
    Config.

end_per_suite(_Config) ->
    ok = application:unload(opentelemetry),
    ok.

init_per_testcase(_, Config) ->
    {ok, _} = application:ensure_all_started(telemetry),
    {ok, _} = application:ensure_all_started(telemetry_registry),
    {ok, _} = application:ensure_all_started(test_app),
    {ok, _} = application:ensure_all_started(opentelemetry_telemetry),
    {ok, _} = application:ensure_all_started(opentelemetry),
    ot_batch_processor:set_exporter(ot_exporter_pid, self()),
    otel_telemetry:init(test_app),
    Config.

end_per_testcase(_, Config) ->
    application:stop(telemetry),
    application:stop(telemetry_registry),
    application:stop(telemetry_app),
    application:stop(opentelemetry_telemetry),
    application:stop(opentelemetry),
    Config.

successful_span(_Config) ->
    _Result = test_app:handler(ok),
    receive
        {span, #span{name=Name,attributes=Attributes}} ->
            ?assertEqual(<<"test_app_handler">>, Name),
            Attr = maps:from_list(Attributes),
            ?assert(maps:is_key(<<"duration">>, Attr))
        after
            5000 ->
                error(timeout)
        end,
    ok.

exception_span(_Config) ->
    try test_app:handler(raise_exception) of
        _ -> ok
    catch
        error:badarg -> ok
    end,
    receive
        {span, #span{name=Name,attributes=Attributes, status=Status}} ->
            ?assertEqual(<<"test_app_handler">>, Name),
            ?assertEqual({status,'InternalError',<<"badarg">>}, Status),
            Attr = maps:from_list(Attributes),
            ?assert(maps:is_key(<<"kind">>, Attr)),
            ?assert(maps:is_key(<<"reason">>, Attr)),
            ?assert(maps:is_key(<<"stacktrace">>, Attr)),
            ?assert(maps:is_key(<<"duration">>, Attr))
    after
        5000 ->
            error(timeout)
    end,
    ok.
