-module(msync_http_header).
-author("Eric Liang <eric@easemob.com>").

-include("msync_http.hrl").
-export([encode/1, encode/2,		
		 decode/1]).

encode(#msync_http_header{ version = Ver,
						   command = Comm,
						   crypto_method = Crypto,
						   encoding = Encoding,
						   guid = Guid 
						 }) ->
	VerB = fix_size(binary:encode_unsigned(Ver), 4),
	CommB = fix_size(binary:encode_unsigned(Comm), 4),
	CryptoB = fix_size(binary:encode_unsigned(Crypto), 4),
	EncodingB = fix_size(binary:encode_unsigned(Encoding), 4),
	HeaderBin = <<VerB/bits, CommB/bits, CryptoB/bits, EncodingB/bits, Guid/bits>>,
	base64:encode(HeaderBin).

encode(Jid, Comm) when is_binary(Jid) ->
	Header = #msync_http_header{ version = ?MSYNC_VERSION,
								 command = Comm,
								 crypto_method = ?MSYNC_CM_NO_CRYPTO,
								 encoding = ?MSYNC_ENC_JSON,
								 guid = tlv(?MSYNC_TAG_GUID, Jid)
							   },
	encode(Header).

decode(HeaderStr) ->
	HeaderBin = base64:decode(HeaderStr),
	<<VerB:4/bits, CommB:4/bits, CryptoB:4/bits, EncodingB:4/bits, 
	  TLVs/bits>> = HeaderBin,
	Header = #msync_http_header{ version = bin_to_unsigned(VerB),
								 command = bin_to_unsigned(CommB),
								 crypto_method = bin_to_unsigned(CryptoB),
								 encoding = bin_to_unsigned(EncodingB)
							   },
	decode_tlv(Header, TLVs).	

decode_tlv(Header, <<>>) ->
	Header;
decode_tlv(Header, <<TagB:8/bits, LenB:8/bits, TLVs/bits>>) ->	
	Len = bin_to_unsigned(LenB),
	<<Val:Len/binary, TLVs2/binary>> = TLVs,
	Tag = bin_to_unsigned(TagB),
	decode_tlv(add_tag(Header, Tag, Val), TLVs2).

add_tag(Header, ?MSYNC_TAG_GUID, Guid) ->
	Header#msync_http_header{ guid = Guid }.

fix_size(Bin, Size) when is_integer(Size) andalso bit_size(Bin) =< Size ->
	%% padding
	PadSize = Size - bit_size(Bin),
	Bin1 = <<0:PadSize, Bin/bits>>,
	%% io:format("~p ~p ~n", [Bin, Bin1]),
	Bin1;
fix_size(Bin, Size) when is_integer(Size) ->
	%% truncating
	Size1 = bit_size(Bin) - Size,
	<<_:Size1, Bin1/bits>> = Bin,
	%% io:format("~w ~p ~w ~p ~n", [Bin, bit_size(Bin), Bin1, bit_size(Bin1)]),
	Bin1.

bin_to_unsigned(Bin) ->
	Size = bit_size(Bin),
	Size1 = case Size rem 8 of
				 0 ->
					 Size;
				 _ ->
					 (Size div 8 + 1 ) * 8
			 end,
	Bin1 = fix_size(Bin, Size1),
	binary:decode_unsigned(Bin1).

tlv(Tag, Val) when is_binary(Val) ->
	case size(Val) > 65535 of
		true ->
			{error, exceed_max_length};
		_ -> 
			TagB = fix_size(binary:encode_unsigned(Tag), 8),			
			LenB = fix_size(binary:encode_unsigned(size(Val)), 8),
			<<TagB/bits, LenB/bits, Val/bits>>
	end.

%%
%% Tests
%%
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

header_test() ->
	Guid = <<"a@b.com/c">>,
	HeaderStr = msync_http_header:encode(Guid, 1),	
	Header = msync_http_header:decode(HeaderStr),
    ?assertEqual(
       Header#msync_http_header.guid,
       Guid).

-endif.
