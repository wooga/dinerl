-module(dinerl).

-author('Valentino Volonghi <valentino@adroll.com>').

-define(DINERL_DATA, dinerl_data).
-define(ARGS_KEY, args).
-define(NONE, <<"NONE">>).
-define(ALL_OLD, <<"ALL_OLD">>).
-define(UPDATED_OLD, <<"UPDATED_OLD">>).
-define(ALL_NEW, <<"ALL_NEW">>).
-define(UPDATED_NEW, <<"UPDATED_NEW">>).

-include("dinerl_types.hrl").

-export([setup/3, setup/1, setup/0, api/1, api/2, api/3, api/4]).
-export([create_table/4, create_table/5, delete_table/1, delete_table/2]).
-export([describe_table/1, describe_table/2, update_table/3, update_table/4]).
-export([list_tables/0, list_tables/1, list_tables/2, put_item/3, put_item/4]).
-export([delete_item/3, delete_item/4]).
-export([get_item/3, get_item/4, get_item/5]).
-export([get_items/1, get_items/2, get_items/3, get_items/4, get_items/5]).
-export([update_item/3, update_item/4]).
-export([update_item_with_expression/3]).
-export([update_item_with_expression/4]).
-export([update_item_with_expression/5]).
-export([update_item_with_expression/6]).
-export([update_item_with_expression/7]).
-export([query_item/3, query_item/4, query_item/5]).
-export([query/2, query/3, query/4]).
-export([update_data/1]).
-export([batch_write_item/3]).

-spec setup(access_key_id(), secret_access_key(), zone()) -> {ok, clientarguments()}.
setup(AccessKeyId, SecretAccessKey, Zone) ->
    application:set_env(erliam, aws_access_key, AccessKeyId),
    application:set_env(erliam, aws_secret_key, SecretAccessKey),
    setup_(Zone).

-spec setup(zone()) -> {ok, clientarguments()}.
setup(Zone) ->
    setup_(Zone).

-spec setup() -> {ok, clientarguments()}.
setup() ->
    {ok, Zone} = imds:zone(),
    setup_(Zone).

-spec setup_(string()) -> {ok, clientarguments()}.
setup_(Zone) ->
    ets:new(?DINERL_DATA, [named_table, public]),
    R = update_data(Zone),
    timer:apply_interval(1000, ?MODULE, update_data, [Zone]),
    R.

-spec api(method()) -> result().
api(Name) ->
    api(Name, {struct, []}).

-spec api(method(), any()) -> result().
api(Name, Body) ->
    api(Name, Body, undefined).

-spec api(method(), any(), undefined | integer()) -> result().
api(Name, Body, Timeout) ->
    api(Name, Body, Timeout, undefined).

-spec api(method(), any(), undefined | integer(), undefined | zone()) -> result().
api(Name, Body, Timeout, Region) ->
    case catch ets:lookup_element(?DINERL_DATA, ?ARGS_KEY, 2) of
        {'EXIT', {badarg, _}} ->
            {error, missing_credentials, ""};
        {Credentials, Zone, Date} ->
            TargetRegion =
                case Region of
                    undefined ->
                        Zone;
                    _ ->
                        Region
                end,
            dinerl_client:api(Credentials, TargetRegion, Date, Name, Body, Timeout)
    end.

-spec create_table(string() | binary(), keyschema(), integer(), integer()) -> jsonf().
create_table(Name, Key, ReadsPerSecond, WritesPerSecond) ->
    create_table(Name, Key, ReadsPerSecond, WritesPerSecond, undefined).

-spec create_table(string() | binary(),
                   keyschema(),
                   integer(),
                   integer(),
                   undefined | integer()) ->
                      jsonf().
create_table(Name, Key, ReadsPerSecond, WritesPerSecond, Timeout) ->
    api(create_table,
        [{<<"TableName">>, Name},
         {<<"KeySchema">>, Key},
         {<<"ProvisionedThroughput">>,
          [{<<"ReadsPerSecond">>, ReadsPerSecond}, {<<"WritesPerSecond">>, WritesPerSecond}]}],
        Timeout).

delete_table(Name) ->
    describe_table(Name, undefined).

delete_table(Name, Timeout) ->
    api(delete_table, [{<<"TableName">>, Name}], Timeout).

describe_table(Name) ->
    describe_table(Name, undefined).

describe_table(Name, Timeout) ->
    api(describe_table, [{<<"TableName">>, Name}], Timeout).

update_table(Name, ReadsPerSecond, WritesPerSecond) ->
    update_table(Name, ReadsPerSecond, WritesPerSecond, undefined).

update_table(Name, ReadsPerSecond, WritesPerSecond, Timeout) ->
    api(update_table,
        [{<<"TableName">>, Name},
         {<<"ProvisionedThroughput">>,
          [{<<"ReadsPerSecond">>, ReadsPerSecond}, {<<"WritesPerSecond">>, WritesPerSecond}]}],
        Timeout).

list_tables() ->
    list_tables([]).

list_tables(List) ->
    list_tables(List, undefined).

list_tables(List, Timeout) ->
    list_tables(List, [], Timeout).

list_tables([], [], Timeout) ->
    list_tables([], {}, Timeout);
list_tables([], Body, Timeout) ->
    api(list_tables, Body, Timeout);
list_tables([{start_name, Name} | Rest], Acc, Timeout) ->
    list_tables(Rest, [{<<"ExclusiveStartTableName">>, Name} | Acc], Timeout);
list_tables([{limit, N} | Rest], Acc, Timeout) ->
    list_tables(Rest, [{<<"Limit">>, N} | Acc], Timeout).

put_item(Table, Attributes, Options) ->
    put_item(Table, Attributes, Options, undefined).

put_item(Table, Attributes, Options, Timeout) ->
    put_item(Table, Attributes, Options, [], Timeout).

put_item(Table, Attributes, [], PartialBody, Timeout) ->
    api(put_item,
        [{<<"TableName">>, Table}, {<<"Item">>, Attributes} | PartialBody],
        Timeout);
put_item(T, A, [{return, all_old} | Rest], Acc, Timeout) ->
    put_item(T, A, Rest, [{<<"ReturnValues">>, ?ALL_OLD} | Acc], Timeout);
put_item(T, A, [{return, none} | Rest], Acc, Timeout) ->
    put_item(T, A, Rest, [{<<"ReturnValues">>, ?NONE} | Acc], Timeout);
put_item(T, A, [{expected, V} | Rest], Acc, Timeout) ->
    put_item(T, A, Rest, [{<<"Expected">>, attr_updates(V, [])} | Acc], Timeout).

delete_item(Table, Key, Options) ->
    delete_item(Table, Key, Options, undefined).

delete_item(Table, Key, Options, Timeout) ->
    delete_item(Table, Key, Options, [], Timeout).

delete_item(Table, Key, [], PartialBody, Timeout) ->
    api(delete_item, [{<<"TableName">>, Table}, {<<"Key">>, Key} | PartialBody], Timeout);
delete_item(T, K, [{return, all_old} | Rest], Acc, Timeout) ->
    delete_item(T, K, Rest, [{<<"ReturnValues">>, ?ALL_OLD} | Acc], Timeout);
delete_item(T, K, [{return, none} | Rest], Acc, Timeout) ->
    delete_item(T, K, Rest, [{<<"ReturnValues">>, ?NONE} | Acc], Timeout);
delete_item(T, K, [{expected, V} | Rest], Acc, Timeout) ->
    delete_item(T, K, Rest, [{<<"Expected">>, attr_updates(V, [])} | Acc], Timeout).

get_item(Table, Key, Options) ->
    get_item(Table, Key, Options, [], undefined, undefined).

get_item(Table, Key, Options, Timeout) ->
    get_item(Table, Key, Options, [], Timeout, undefined).

get_item(Table, Key, Options, Timeout, Region) ->
    get_item(Table, Key, Options, [], Timeout, Region).

get_item(T, K, [], Acc, Timeout, Region) ->
    api(get_item, [{<<"TableName">>, T}, {<<"Key">>, K} | Acc], Timeout, Region);
get_item(T, K, [{consistent, V} | Rest], Acc, Timeout, Region) ->
    get_item(T, K, Rest, [{<<"ConsistentRead">>, V} | Acc], Timeout, Region);
get_item(T, K, [{attrs, V} | Rest], Acc, Timeout, Region) ->
    get_item(T, K, Rest, [{<<"AttributesToGet">>, V} | Acc], Timeout, Region).

get_items(Table, Keys, Options) ->
    do_get_items([{Table, Keys, Options}], [], undefined, undefined).

get_items(Table, Keys, Options, Timeout) ->
    do_get_items([{Table, Keys, Options}], [], Timeout, undefined).

get_items(Table, Keys, Options, Timeout, Region) ->
    do_get_items([{Table, Keys, Options}], [], Timeout, Region).

get_items(MultiTableQuery) ->
    do_get_items(MultiTableQuery, [], undefined, undefined).

get_items(MultiTableQuery, Timeout) ->
    do_get_items(MultiTableQuery, [], Timeout, undefined).

do_get_items([], Acc, Timeout, Region) ->
    api(batch_get_item, [{<<"RequestItems">>, Acc}], Timeout, Region);
do_get_items([{Table, Keys, Options} | Rest], Acc, Timeout, Region) ->
    Attrs = proplists:get_value(attrs, Options, []),
    do_get_items(Rest, [get_body_request(Table, Keys, Attrs) | Acc], Timeout, Region).

get_body_request(Table, Keys, []) ->
    {Table, [{<<"Keys">>, Keys}]};
get_body_request(Table, Keys, Attrs) ->
    {Table, [{<<"Keys">>, Keys}, {<<"AttributesToGet">>, Attrs}]}.

update_item_with_expression(TableName, Key, UpdateExpression) ->
    update_item_with_expression(TableName,
                                Key,
                                UpdateExpression,
                                undefined,
                                <<"NONE">>,
                                [],
                                undefined).

update_item_with_expression(TableName,
                            Key,
                            UpdateExpression,
                            ExpressionAttributeValues) ->
    update_item_with_expression(TableName,
                                Key,
                                UpdateExpression,
                                ExpressionAttributeValues,
                                <<"NONE">>,
                                [],
                                undefined).

update_item_with_expression(TableName,
                            Key,
                            UpdateExpression,
                            ExpressionAttributeValues,
                            ReturnValues) ->
    update_item_with_expression(TableName,
                                Key,
                                UpdateExpression,
                                ExpressionAttributeValues,
                                ReturnValues,
                                [],
                                undefined).

update_item_with_expression(TableName,
                            Key,
                            UpdateExpression,
                            ExpressionAttributeValues,
                            ReturnValues,
                            Acc) ->
    update_item_with_expression(TableName,
                                Key,
                                UpdateExpression,
                                ExpressionAttributeValues,
                                ReturnValues,
                                Acc,
                                undefined).

update_item_with_expression(TableName,
                            Key,
                            UpdateExpression,
                            ExpressionAttributeValues,
                            ReturnValues,
                            Acc,
                            Timeout) ->
    MandatoryParams =
        [{<<"TableName">>, TableName},
         {<<"Key">>, Key},
         {<<"UpdateExpression">>, UpdateExpression}],
    OptionalParams =
        [{<<"ExpressionAttributeValues">>, ExpressionAttributeValues},
         {<<"ReturnValues">>, ReturnValues}],
    DefinedOptionalParams =
        lists:filter(fun ({_, undefined}) ->
                             false;
                         (_) ->
                             true
                     end,
                     OptionalParams),

    api(update_item, MandatoryParams ++ DefinedOptionalParams ++ Acc, Timeout).

update_item(Table, Key, Options) ->
    update_item(Table, Key, Options, undefined).

update_item(Table, Key, Options, Timeout) ->
    update_item(Table, Key, Options, [], Timeout).

update_item(T, K, [], Acc, Timeout) ->
    api(update_item, [{<<"TableName">>, T}, {<<"Key">>, K} | Acc], Timeout);
update_item(T, K, [{update, AttributeUpdates} | Rest], Acc, Timeout) ->
    update_item(T,
                K,
                Rest,
                [{<<"AttributeUpdates">>, attr_updates(AttributeUpdates, [])} | Acc],
                Timeout);
update_item(T, K, [{expected, V} | Rest], Acc, Timeout) ->
    update_item(T, K, Rest, [{<<"Expected">>, attr_updates(V, [])} | Acc], Timeout);
update_item(T, K, [{return, none} | Rest], Acc, Timeout) ->
    update_item(T, K, Rest, [{<<"ReturnValues">>, ?NONE} | Acc], Timeout);
update_item(T, K, [{return, all_old} | Rest], Acc, Timeout) ->
    update_item(T, K, Rest, [{<<"ReturnValues">>, ?ALL_OLD} | Acc], Timeout);
update_item(T, K, [{return, updated_old} | Rest], Acc, Timeout) ->
    update_item(T, K, Rest, [{<<"ReturnValues">>, ?UPDATED_OLD} | Acc], Timeout);
update_item(T, K, [{return, all_new} | Rest], Acc, Timeout) ->
    update_item(T, K, Rest, [{<<"ReturnValues">>, ?ALL_NEW} | Acc], Timeout);
update_item(T, K, [{return, updated_new} | Rest], Acc, Timeout) ->
    update_item(T, K, Rest, [{<<"ReturnValues">>, ?UPDATED_NEW} | Acc], Timeout).

%% query_item options:
%% Uses amazon api version:
%% http://docs.aws.amazon.com/amazondynamodb/latest/developerguide/API_Query_v20111205.html
%% limit: int, max number of results
%% count: bool, only return the total count
%% scan_index_forward: bool, set to false to reverse the sort order
%% consistent: bool, make a consistent read, default false
%% exclusive_start_key: output from LastEvaluatedKey when limit(size or limit param) is reached
%% attrs: array( binary ), [<<"a">>,<<"b">>], only return these attributes
%% range_condition: {array( attributes), operation }
%% eg, dinerl:query_item(<<"table">>,[{<<"S">>, <<"hash_value">>}],
%%   [{range_condition, { [[{<<"S">>, <<"range_value">>}]]  ,<<"EQ">> }}]).
query_item(Table, Key, Options) ->
    query_item(Table, Key, Options, [], undefined, undefined).

query_item(Table, Key, Options, Timeout) ->
    query_item(Table, Key, Options, [], Timeout, undefined).

query_item(Table, Key, Options, Timeout, Region) ->
    query_item(Table, Key, Options, [], Timeout, Region).

query_item(T, K, List, Acc, Timeout, Region) ->
    NewParameters =
        [{<<"TableName">>, T}, {<<"HashKeyValue">>, K} | convert_query_parameters(List, Acc)],
    api(query_item_20111205, NewParameters, Timeout, Region).

%% Uses new API
query(Table, Options) ->
    query(Table, Options, undefined, undefined).

query(Table, Options, Timeout) ->
    query(Table, Options, Timeout, undefined).

query(Table, Options, Timeout, Region) ->
    NewParameters = [{<<"TableName">>, Table} | convert_query_parameters(Options, [])],
    api(query_item_20120810, NewParameters, Timeout, Region).

convert_query_parameters([], Acc) ->
    Acc;
convert_query_parameters([{limit, V} | Rest], Acc) ->
    convert_query_parameters(Rest, [{<<"Limit">>, V} | Acc]);
convert_query_parameters([{count, V} | Rest], Acc) ->
    convert_query_parameters(Rest, [{<<"Count">>, V} | Acc]);
convert_query_parameters([{index_name, IndexName} | Rest], Acc) ->
    convert_query_parameters(Rest, [{<<"IndexName">>, IndexName} | Acc]);
convert_query_parameters([{scan_index_forward, V} | Rest], Acc) ->
    convert_query_parameters(Rest, [{<<"ScanIndexForward">>, V} | Acc]);
convert_query_parameters([{consistent, V} | Rest], Acc) ->
    convert_query_parameters(Rest, [{<<"ConsistentRead">>, V} | Acc]);
convert_query_parameters([{exclusive_start_key, V} | Rest], Acc) ->
    convert_query_parameters(Rest, [{<<"ExclusiveStartKey">>, V} | Acc]);
convert_query_parameters([{range_condition, {V, Op}} | Rest], Acc) ->
    convert_query_parameters(Rest,
                             [{<<"RangeKeyCondition">>,
                               [{<<"AttributeValueList">>, V}, {<<"ComparisonOperator">>, Op}]}
                              | Acc]);
convert_query_parameters([{attrs, V} | Rest], Acc) ->
    convert_query_parameters(Rest, [{<<"AttributesToGet">>, V} | Acc]);
convert_query_parameters([{project_expression, ProjectionExpression} | Rest], Acc) ->
    convert_query_parameters(Rest,
                             [{<<"ProjectionExpression">>, ProjectionExpression} | Acc]);
convert_query_parameters([{key_condition_expression, KeyConditionExpression} | Rest],
                         Acc) ->
    convert_query_parameters(Rest,
                             [{<<"KeyConditionExpression">>, KeyConditionExpression} | Acc]);
convert_query_parameters([{condition_expression, KeyConditionExpression} | Rest], Acc) ->
    convert_query_parameters(Rest,
                             [{<<"ConditionExpression">>, KeyConditionExpression} | Acc]);
convert_query_parameters([{filter_expression, KeyConditionExpression} | Rest], Acc) ->
    convert_query_parameters(Rest, [{<<"FilterExpression">>, KeyConditionExpression} | Acc]);
convert_query_parameters([{expression_attribute_values, ExpressionAttributeValues}
                          | Rest],
                         Acc) ->
    convert_query_parameters(Rest,
                             [{<<"ExpressionAttributeValues">>, ExpressionAttributeValues} | Acc]);
convert_query_parameters([{expression_attribute_names, ExpressionAttributeNames} | Rest],
                         Acc) ->
    convert_query_parameters(Rest,
                             [{<<"ExpressionAttributeNames">>, ExpressionAttributeNames} | Acc]).

batch_write_item(TableName, PutItems, DeleteKeys) ->
    api(batch_write_item,
        [{<<"RequestItems">>,
          [{TableName,
            lists:map(fun make_batch_put/1, PutItems)
            ++ lists:map(fun make_batch_delete/1, DeleteKeys)}]}]).

make_batch_put(Item) ->
    [{<<"PutRequest">>, [{<<"Item">>, Item}]}].

make_batch_delete(Key) ->
    [{<<"DeleteRequest">>, [{<<"Key">>, Key}]}].

%% Internal
%%
%% Every second it updates the Date part of the arguments and copies the latest cached
%% credentials from erliam.
-spec update_data(zone()) -> {ok, clientarguments()}.
update_data(Zone) ->
    NewDate = awsv4:isonow(),
    NewArgs = {erliam:credentials(), Zone, NewDate},
    ets:insert(?DINERL_DATA, {?ARGS_KEY, NewArgs}),
    {ok, NewArgs}.

expected([], Acc) ->
    Acc;
expected([{Option, Value} | Rest], Acc) ->
    expected(Rest, [value_and_action({Option, Value}) | Acc]).

attr_updates([], Acc) ->
    Acc;
attr_updates([{AttrName, Opts} | Rest], Acc) ->
    attr_updates(Rest, [{AttrName, expected(Opts, [])} | Acc]).

value_and_action({value, V}) ->
    {<<"Value">>, V};
value_and_action({action, put}) ->
    {<<"Action">>, <<"PUT">>};
value_and_action({action, add}) ->
    {<<"Action">>, <<"ADD">>};
value_and_action({action, delete}) ->
    {<<"Action">>, <<"DELETE">>};
value_and_action({exists, V}) ->
    {<<"Exists">>, V}.
