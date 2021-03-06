%% @doc: Collection of functions for sending statistics from the

-module(statman_vm_metrics).
-compile([export_all]).


get_counters() ->
    {{input, InputBytes}, {output, OutputBytes}} = erlang:statistics(io),
    [{{vm, io_in_bytes}, InputBytes}, {{vm, io_out_bytes}, OutputBytes}].


get_gauges() ->
    Memory = lists:map(fun({K, V}) ->
        {{vm_memory, K}, V}
                       end, erlang:memory()),

    RunQueue = {{vm, run_queue}, erlang:statistics(run_queue)},
    ProcessCount = {{vm, process_count}, erlang:system_info(process_count)},

    [RunQueue, ProcessCount] ++ Memory ++ message_stats() ++ ets_stats() ++ mnesia_table_size().


message_stats() ->
    ProcessInfo = lists:flatmap(
        fun(Pid) ->
            case process_info(Pid, message_queue_len) of
                undefined ->
                    [];
                {message_queue_len, 0} ->
                    [];
                {message_queue_len, Count} ->
                    [{Count, Pid}]
            end
        end, processes()),
    TotalQueue = lists:sum(element(1, lists:unzip(ProcessInfo))),

    [{{vm, processes_with_queues}, length(ProcessInfo)},
        {{vm, messages_in_queue}, TotalQueue}].

ets_stats() ->
    EtsList = lists:filtermap(fun(T) when is_atom(T) ->
        {true, case ets:info(T, size) of
                   N when is_integer(N) -> {T, N};
                   undefined -> {T, 0}
               end};
        (_) -> false
                              end,
        ets:all()),
    TotalSize = lists:sum(lists:map(fun({_, Size}) -> Size end, EtsList)),

    Top10 = lists:sublist(lists:reverse(lists:keysort(2, EtsList)), 1, 10),
    io:format("ets table top10:~p~n", [Top10]),
    [{{vm_ets, total_size}, TotalSize} | lists:map(fun({ET, Size}) -> {{vm_ets, ET}, Size} end, Top10)].

mnesia_table_size() ->
    SessionSize = mnesia:table_info(session, size),
    LastActivitySize = mnesia:table_info(last_activity, size),
    VcardSize = mnesia:table_info(vcard, size),
    [{{mnesia, session_size}, SessionSize}
        , {{mnesia, last_activity_size}, LastActivitySize}
        , {{mnesia, vcard_size}, VcardSize}
    ].

io(undefined) ->
    {{input, InputBytes}, {output, OutputBytes}} = erlang:statistics(io),
    {{InputBytes, OutputBytes}, []};
io({PrevInputBytes, PrevOutputBytes}) ->
    {{input, InputBytes}, {output, OutputBytes}} = erlang:statistics(io),
    {{InputBytes, OutputBytes}, [{{vm, io_in_bytes}, InputBytes - PrevInputBytes}, {{vm, io_out_bytes}, OutputBytes - PrevOutputBytes}]}.

gc(undefined) ->
    {NumGCs, _, _} = erlang:statistics(garbage_collection),
    {NumGCs, []};
gc(PrevNumGCs) ->
    {NumGCs, _, 0} = erlang:statistics(garbage_collection),
    {NumGCs, [{{vm, gcs}, NumGCs - PrevNumGCs}]}.
