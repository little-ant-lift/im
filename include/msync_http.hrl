-define(MSYNC_VERSION, 1).
-define(MSYNC_COMM_UNREAD, 1).
-define(MSYNC_COMM_SYNC, 1).
-define(MSYNC_CM_NO_CRYPTO, 0).
-define(MSYNC_ENC_JSON, 1).
-define(MSYNC_TAG_GUID, 1).

-record(msync_http_header, 
		{ version, 
		  command, 
		  crypto_method,
		  encoding,
		  %% TLV parameters
		  user_agent,
		  guid,
		  pov,
		  auth
		}).
