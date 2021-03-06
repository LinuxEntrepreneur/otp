%%
%% %CopyrightBegin%
%%
%% Copyright Ericsson AB 2010-2013. All Rights Reserved.
%%
%% The contents of this file are subject to the Erlang Public License,
%% Version 1.1, (the "License"); you may not use this file except in
%% compliance with the License. You should have received a copy of the
%% Erlang Public License along with this software. If not, it can be
%% retrieved online at http://www.erlang.org/.
%%
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and limitations
%% under the License.
%%
%% %CopyrightEnd%
%%

%%
%% This file contains code that's included by encode/decode modules
%% generated by diameter_codegen.erl. This code does most of the work, the
%% generated code being kept simple.
%%

-define(THROW(T), throw({?MODULE, T})).

-type parent_name()   :: atom().  %% parent = Message or AVP
-type parent_record() :: tuple(). %%
-type avp_name()   :: atom().
-type avp_record() :: tuple().
-type avp_values() :: [{avp_name(), term()}].

-type non_grouped_avp() :: #diameter_avp{}.
-type grouped_avp() :: nonempty_improper_list(#diameter_avp{}, [avp()]).
-type avp() :: non_grouped_avp() | grouped_avp().

%% ---------------------------------------------------------------------------
%% # encode_avps/2
%% ---------------------------------------------------------------------------

-spec encode_avps(parent_name(), parent_record() | avp_values())
   -> binary()
    | no_return().

encode_avps(Name, Vals)
  when is_list(Vals) ->
    encode_avps(Name, '#set-'(Vals, newrec(Name)));

encode_avps(Name, Rec) ->
    try
        list_to_binary(encode(Name, Rec))
    catch
        throw: {?MODULE, Reason} ->
            diameter_lib:log({encode, error},
                             ?MODULE,
                             ?LINE,
                             {Reason, Name, Rec}),
            erlang:error(list_to_tuple(Reason ++ [Name]));
        error: Reason ->
            Stack = erlang:get_stacktrace(),
            diameter_lib:log({encode, failure},
                             ?MODULE,
                             ?LINE,
                             {Reason, Name, Rec, Stack}),
            erlang:error({encode_failure, Reason, Name, Stack})
    end.

%% encode/2

encode(Name, Rec) ->
    lists:flatmap(fun(A) -> encode(Name, A, '#get-'(A, Rec)) end,
                  '#info-'(element(1, Rec), fields)).

%% encode/3

encode(Name, AvpName, Values) ->
    e(Name, AvpName, avp_arity(Name, AvpName), Values).

%% e/4

e(_, AvpName, 1, undefined) ->
    ?THROW([mandatory_avp_missing, AvpName]);

e(Name, AvpName, 1, Value) ->
    e(Name, AvpName, [Value]);

e(_, _, {0,_}, []) ->
    [];

e(_, AvpName, _, T)
  when not is_list(T) ->
    ?THROW([repeated_avp_as_non_list, AvpName, T]);

e(_, AvpName, {Min, _}, L)
  when length(L) < Min ->
    ?THROW([repeated_avp_insufficient_arity, AvpName, Min, L]);

e(_, AvpName, {_, Max}, L)
  when Max < length(L) ->
    ?THROW([repeated_avp_excessive_arity, AvpName, Max, L]);

e(Name, AvpName, _, Values) ->
    e(Name, AvpName, Values).

%% e/3

e(Name, 'AVP', Values) ->
    [pack_AVP(Name, A) || A <- Values];

e(_, AvpName, Values) ->
    e(AvpName, Values).

%% e/2

e(AvpName, Values) ->
    H = avp_header(AvpName),
    [diameter_codec:pack_avp(H, avp(encode, V, AvpName)) || V <- Values].

%% pack_AVP/2

%% No value: assume AVP data is already encoded. The normal case will
%% be when this is passed back from #diameter_packet.errors as a
%% consequence of a failed decode. Any AVP can be encoded this way
%% however, which side-steps any arity checks for known AVP's and
%% could potentially encode something unfortunate.
pack_AVP(_, #diameter_avp{value = undefined} = A) ->
    diameter_codec:pack_avp(A);

%% Missing name for value encode.
pack_AVP(_, #diameter_avp{name = N, value = V})
  when N == undefined;
       N == 'AVP' ->
    ?THROW([value_with_nameless_avp, N, V]);

%% Or not. Ensure that 'AVP' is the appropriate field. Note that if we
%% don't know this AVP at all then the encode will fail.
pack_AVP(Name, #diameter_avp{name = AvpName,
                             value = Data}) ->
    0 == avp_arity(Name, AvpName)
        orelse ?THROW([known_avp_as_AVP, Name, AvpName, Data]),
    e(AvpName, [Data]).

%% ---------------------------------------------------------------------------
%% # decode_avps/2
%% ---------------------------------------------------------------------------

-spec decode_avps(parent_name(), [#diameter_avp{}])
   -> {parent_record(), [avp()], Failed}
 when Failed :: [{5000..5999, #diameter_avp{}}].

decode_avps(Name, Recs) ->
    {Avps, {Rec, Failed}}
        = lists:foldl(fun(T,A) -> decode(Name, T, A) end,
                      {[], {newrec(Name), []}},
                      Recs),
    {Rec, Avps, Failed ++ missing(Rec, Name)}.
%% Append 5005 errors so that a 5014 for the same AVP will take
%% precedence in a Result-Code/Failed-AVP setting.

newrec(Name) ->
    '#new-'(name2rec(Name)).

%% 3588:
%%
%%   DIAMETER_MISSING_AVP               5005
%%      The request did not contain an AVP that is required by the Command
%%      Code definition.  If this value is sent in the Result-Code AVP, a
%%      Failed-AVP AVP SHOULD be included in the message.  The Failed-AVP
%%      AVP MUST contain an example of the missing AVP complete with the
%%      Vendor-Id if applicable.  The value field of the missing AVP
%%      should be of correct minimum length and contain zeroes.

missing(Rec, Name) ->
    [{5005, empty_avp(F)} || F <- '#info-'(element(1, Rec), fields),
                             A <- [avp_arity(Name, F)],
                             false <- [have_arity(A, '#get-'(F, Rec))]].

%% Maximum arities have already been checked in building the record.

have_arity({Min, _}, L) ->
    Min =< length(L);
have_arity(N, V) ->
    N /= 1 orelse V /= undefined.

%% empty_avp/1

empty_avp(Name) ->
    {Code, Flags, VId} = avp_header(Name),
    {Name, Type} = avp_name(Code, VId),
    #diameter_avp{name = Name,
                  code = Code,
                  vendor_id = VId,
                  is_mandatory = 0 /= (Flags band 2#01000000),
                  need_encryption = 0 /= (Flags band 2#00100000),
                  data = empty_value(Name),
                  type = Type}.

%% 3588, ch 7:
%%
%%   The Result-Code AVP describes the error that the Diameter node
%%   encountered in its processing.  In case there are multiple errors,
%%   the Diameter node MUST report only the first error it encountered
%%   (detected possibly in some implementation dependent order).  The
%%   specific errors that can be described by this AVP are described in
%%   the following section.

%% decode/3

decode(Name, #diameter_avp{code = Code, vendor_id = Vid} = Avp, Acc) ->
    decode(Name, avp_name(Code, Vid), Avp, Acc).

%% decode/4

decode(Name, {AvpName, Type}, Avp, Acc) ->
    d(Name, Avp#diameter_avp{name = AvpName, type = Type}, Acc);

decode(Name, 'AVP', Avp, Acc) ->
    decode_AVP(Name, Avp, Acc).

%% d/3

%% Don't try to decode the value of a Failed-AVP component since it
%% probably won't. Note that matching on 'Failed-AVP' assumes that
%% this is the RFC AVP, with code 279. Strictly, this doesn't need to
%% be the case, so we're assuming no one defines another Failed-AVP.
d('Failed-AVP' = Name, Avp, Acc) ->
    decode_AVP(Name, Avp, Acc);

%% Or try to decode.
d(Name, Avp, {Avps, Acc}) ->
    #diameter_avp{name = AvpName,
                  data = Data}
        = Avp,

    try avp(decode, Data, AvpName) of
        V ->
            {H, A} = ungroup(V, Avp),
            {[H | Avps], pack_avp(Name, A, Acc)}
    catch
        error: Reason ->
            %% Failures here won't be visible since they're a "normal"
            %% occurrence if the peer sends a faulty AVP that we need to
            %% respond sensibly to. Log the occurence for traceability,
            %% but the peer will also receive info in the resulting
            %% answer-message.
            diameter_lib:log({decode, failure},
                             ?MODULE,
                             ?LINE,
                             {Reason, Avp, erlang:get_stacktrace()}),
            {Rec, Failed} = Acc,
            {[Avp|Avps], {Rec, [rc(Reason, Avp) | Failed]}}
    end.

%% decode_AVP/3
%%
%% Don't know this AVP: see if it can be packed in an 'AVP' field
%% undecoded. Note that the type field is 'undefined' in this case.

decode_AVP(Name, Avp, {Avps, Acc}) ->
    {[Avp | Avps], pack_AVP(Name, Avp, Acc)}.

%% rc/1

%% diameter_types will raise an error of this form to communicate
%% DIAMETER_INVALID_AVP_LENGTH (5014). A module specified to a
%% @custom_types tag in a spec file can also raise an error of this
%% form.
rc({'DIAMETER', 5014 = RC, _}, #diameter_avp{name = AvpName} = Avp) ->
    {RC, Avp#diameter_avp{data = empty_value(AvpName)}};

%% 3588:
%%
%%   DIAMETER_INVALID_AVP_VALUE         5004
%%      The request contained an AVP with an invalid value in its data
%%      portion.  A Diameter message indicating this error MUST include
%%      the offending AVPs within a Failed-AVP AVP.
rc(_, Avp) ->
    {5004, Avp}.

%% ungroup/2

-spec ungroup(term(), #diameter_avp{})
   -> {avp(), #diameter_avp{}}.

%% The decoded value in the Grouped case is as returned by grouped_avp/3:
%% a record and a list of component AVP's.
ungroup(V, #diameter_avp{type = 'Grouped'} = Avp) ->
    {Rec, As} = V,
    A = Avp#diameter_avp{value = Rec},
    {[A|As], A};

%% Otherwise it's just a plain value.
ungroup(V, #diameter_avp{} = Avp) ->
    A = Avp#diameter_avp{value = V},
    {A, A}.

%% pack_avp/3

pack_avp(Name, #diameter_avp{name = AvpName} = Avp, Acc) ->
    pack_avp(Name, avp_arity(Name, AvpName), Avp, Acc).

%% pack_avp/4

pack_avp(Name, 0, Avp, Acc) ->
    pack_AVP(Name, Avp, Acc);

pack_avp(_, Arity, Avp, Acc) ->
    pack(Arity, Avp#diameter_avp.name, Avp, Acc).

%% pack_AVP/3

%% Give Failed-AVP special treatment since it'll contain any
%% unrecognized mandatory AVP's.
pack_AVP(Name, #diameter_avp{is_mandatory = true} = Avp, Acc)
  when Name /= 'Failed-AVP' ->
    {Rec, Failed} = Acc,
    {Rec, [{5001, Avp} | Failed]};

pack_AVP(Name, #diameter_avp{is_mandatory = M} = Avp, Acc) ->
    case avp_arity(Name, 'AVP') of
        0 ->
            {Rec, Failed} = Acc,
            {Rec, [{if M -> 5001; true -> 5008 end, Avp} | Failed]};
        Arity ->
            pack(Arity, 'AVP', Avp, Acc)
    end.

%% 3588:
%%
%%   DIAMETER_AVP_UNSUPPORTED           5001
%%      The peer received a message that contained an AVP that is not
%%      recognized or supported and was marked with the Mandatory bit.  A
%%      Diameter message with this error MUST contain one or more Failed-
%%      AVP AVP containing the AVPs that caused the failure.
%%
%%   DIAMETER_AVP_NOT_ALLOWED           5008
%%      A message was received with an AVP that MUST NOT be present.  The
%%      Failed-AVP AVP MUST be included and contain a copy of the
%%      offending AVP.

%% pack/4

pack(Arity, FieldName, Avp, {Rec, _} = Acc) ->
    pack('#get-'(FieldName, Rec), Arity, FieldName, Avp, Acc).

%% pack/5

pack(undefined, 1, FieldName, Avp, Acc) ->
    p(FieldName, fun(V) -> V end, Avp, Acc);

%% 3588:
%%
%%   DIAMETER_AVP_OCCURS_TOO_MANY_TIMES 5009
%%      A message was received that included an AVP that appeared more
%%      often than permitted in the message definition.  The Failed-AVP
%%      AVP MUST be included and contain a copy of the first instance of
%%      the offending AVP that exceeded the maximum number of occurrences
%%
pack(_, 1, _, Avp, {Rec, Failed}) ->
    {Rec, [{5009, Avp} | Failed]};
pack(L, {_, Max}, _, Avp, {Rec, Failed})
  when length(L) == Max ->
    {Rec, [{5009, Avp} | Failed]};

pack(L, _, FieldName, Avp, Acc) ->
    p(FieldName, fun(V) -> [V|L] end, Avp, Acc).

%% p/4

p(F, Fun, Avp, {Rec, Failed}) ->
    {'#set-'({F, Fun(value(F, Avp))}, Rec), Failed}.

value('AVP', Avp) ->
    Avp;
value(_, Avp) ->
    Avp#diameter_avp.value.

%% ---------------------------------------------------------------------------
%% # grouped_avp/3
%% ---------------------------------------------------------------------------

-spec grouped_avp(decode, avp_name(), binary())
   -> {avp_record(), [avp()]};
                 (encode, avp_name(), avp_record() | avp_values())
   -> binary()
    | no_return().

grouped_avp(decode, Name, Data) ->
    {Rec, Avps, []} = decode_avps(Name, diameter_codec:collect_avps(Data)),
    {Rec, Avps};
%% A failed match here will result in 5004. Note that this is the only
%% AVP type that doesn't just return the decoded record, also
%% returning the list of component AVP's.

grouped_avp(encode, Name, Data) ->
    encode_avps(Name, Data).

%% ---------------------------------------------------------------------------
%% # empty_group/1
%% ---------------------------------------------------------------------------

empty_group(Name) ->
    list_to_binary(empty_body(Name)).

empty_body(Name) ->
    [z(F, avp_arity(Name, F)) || F <- '#info-'(name2rec(Name), fields)].

z(Name, 1) ->
    z(Name);
z(_, {0,_}) ->
    [];
z(Name, {Min, _}) ->
    lists:duplicate(Min, z(Name)).

z('AVP') ->
    <<0:64/integer>>;  %% minimal header
z(Name) ->
    Bin = diameter_codec:pack_avp(avp_header(Name), empty_value(Name)),
    << <<0>> || <<_>> <= Bin >>.

%% ---------------------------------------------------------------------------
%% # empty/1
%% ---------------------------------------------------------------------------

empty(AvpName) ->
    avp(encode, zero, AvpName).
