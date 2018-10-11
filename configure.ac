#                                               -*- Autoconf -*-
# Process this file with autoconf to produce a configure script.

AC_PREREQ(2.53)
m4_define([digit_tag], [m4_normalize(m4_esyscmd([git describe --tags --match="[0-9]*.[0-9]*" --abbrev=0 2>/dev/null || echo 0.0]))])dnl
m4_define([commit_num], [m4_normalize(m4_esyscmd([git rev-list ]digit_tag[..HEAD 2>/dev/null | wc -l]))])dnl
m4_define([community_version], [m4_join([.], [digit_tag], [commit_num])])dnl
AC_INIT(msync, community_version, [eric@easemob.com], [easemob.com])
REQUIRE_ERLANG_MIN="6.0 (Erlang/OTP R17)"
REQUIRE_ERLANG_MAX="9.0.0 (No Max)"

# Checks for programs.
AC_PROG_MAKE_SET
AC_PROG_INSTALL
AC_PROG_SED

if test "x$GCC" = "xyes"; then
    CFLAGS="$CFLAGS -Wall"
fi

# Checks Erlang runtime and compiler
AC_ARG_WITH(erlang,
	AC_HELP_STRING([--with-erlang=dir],
		[search for erlang in dir]),
[if test "$withval" = "yes" -o "$withval" = "no" -o "X$with_erlang" = "X"; then
    extra_erl_path=""
else
    extra_erl_path="$with_erlang:$with_erlang/bin:"
fi
])

AC_PATH_TOOL(ERL, erl, , [${extra_erl_path}$PATH])
AC_PATH_TOOL(ERLC, erlc, , [${extra_erl_path}$PATH])

AC_ERLANG_NEED_ERL
AC_ERLANG_NEED_ERLC

AC_ARG_ENABLE(erlang-version-check,
[AC_HELP_STRING([--enable-erlang-version-check],
	[Check Erlang/OTP version @<:@default=yes@:>@])])
case "$enable_erlang_version_check" in
	yes|'')
		ERLANG_VERSION_CHECK([$REQUIRE_ERLANG_MIN],[$REQUIRE_ERLANG_MAX])
		;;
	no)
		ERLANG_VERSION_CHECK([$REQUIRE_ERLANG_MIN],[$REQUIRE_ERLANG_MAX],[warn])
		;;
esac

# Checks and sets ERLANG_ROOT_DIR and ERLANG_LIB_DIR variable
AC_ERLANG_SUBST_ROOT_DIR
# AC_ERLANG_SUBST_LIB_DIR

#locating escript
AC_PATH_PROG([ESCRIPT], [escript], [], [$ERLANG_ROOT_DIR/bin])

#locating make
AC_CHECK_PROG([MAKE], [make], [make], [])

if test "x$ESCRIPT" = "x"; then
   AC_MSG_ERROR(['escript' was not found])
fi

if test "x$MAKE" = "x"; then
   AC_MSG_ERROR(['make' was not found])
fi

# Change default prefix
AC_PREFIX_DEFAULT(/)


AC_ARG_ENABLE(hipe,
[AC_HELP_STRING([--enable-hipe], [compile natively with HiPE, not recommended (default: no)])],
[case "${enableval}" in
  yes) hipe=true ;;
  no)  hipe=false ;;
  *) AC_MSG_ERROR(bad value ${enableval} for --enable-hipe) ;;
esac],[hipe=true])


AC_ARG_ENABLE(shard,
[AC_HELP_STRING([--enable-shard], [enable shard support (default: yes)])],
[case "${enableval}" in
  yes) shard=true ;;
  no)  shard=false ;;
  *) AC_MSG_ERROR(bad value ${enableval} for --enable-shard) ;;
esac],[if test "x$shard" = "x"; then shard=true; fi])

AC_ARG_ENABLE(debug,
[AC_HELP_STRING([--enable-debug], [enable debug information (default: no)])],
[case "${enableval}" in
  yes) debug=true ;;
  no)  debug=false ;;
  *) AC_MSG_ERROR(bad value ${enableval} for --enable-debug) ;;
esac],[if test "x$debug" = "x"; then debug=false; fi])



AC_ARG_ENABLE(license,
[AC_HELP_STRING([--enable-license], [build with license checking, default: no)])],
[case "${enableval}" in
  yes) license=true
       if test -f tools/private_key.pem ; then rm -f tools/private_key.pem ; fi
       openssl genrsa -out tools/private_key.pem 4096
       chmod 400 tools/private_key.pem
       openssl rsa -pubout -in tools/private_key.pem -out tools/public_key.pem
       tools/generate_license_data tools/public_key.pem > src/ejabberd_license_data.erl
       ;;
  no)  license=false ;;
  *) AC_MSG_ERROR(bad value ${enableval} for --enable-license) ;;
esac],[if test "x$license" = "x"; then license=false; fi])

AC_ARG_VAR(INITIAL_LICENSE_TIME, [how long the license is active since the last built, in second. Default value is 604800, i.e. one week])

if test "x$INITIAL_LICENSE_TIME" = "x"; then INITIAL_LICENSE_TIME=604800; fi


AC_CONFIG_FILES([vars.config])

AC_ERLANG_CHECK_LIB([sasl], [],
    [AC_MSG_ERROR([Erlang application 'sasl' was not found])])
AC_ERLANG_CHECK_LIB([crypto], [],
    [AC_MSG_ERROR([Erlang application 'crypto' was not found])])
AC_ERLANG_CHECK_LIB([public_key], [],
    [AC_MSG_ERROR([Erlang application 'public_key' was not found])])
AC_ERLANG_CHECK_LIB([ssl], [],
    [AC_MSG_ERROR([Erlang application 'ssl' was not found])])
AC_ERLANG_CHECK_LIB([mnesia], [],
    [AC_MSG_ERROR([Erlang application 'mnesia' was not found])])
AC_ERLANG_CHECK_LIB([inets], [],
    [AC_MSG_ERROR([Erlang application 'inets' was not found])])
AC_ERLANG_CHECK_LIB([compiler], [],
    [AC_MSG_ERROR([Erlang application 'compiler' was not found])])
if test "x$odbc" = "xtrue"; then
   AC_ERLANG_CHECK_LIB([odbc], [],
      [AC_MSG_ERROR([Erlang application 'odbc' was not found])])
fi
if test "x$tools" = "xtrue"; then
   AC_ERLANG_CHECK_LIB([tools], [],
      [AC_MSG_ERROR([Erlang application 'tools' was not found])])
   AC_ERLANG_CHECK_LIB([runtime_tools], [],
      [AC_MSG_ERROR([Erlang application 'runtime_tools' was not found])])
fi

AC_SUBST(shard)
AC_SUBST(debug)
AC_SUBST(license)
AC_SUBST(hipe)

AC_OUTPUT
