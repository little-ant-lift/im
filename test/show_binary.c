/* niftest.c */
#include <stdio.h>
#include <stdlib.h>
#include "erl_nif.h"

static ERL_NIF_TERM show(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
    ErlNifSInt64 ptr;
    int size;
    if(! enif_get_int64(env, argv[0], &ptr) ){
        return enif_make_badarg(env);
    }
    if(! enif_get_int(env, argv[1], &size) ){
        return enif_make_badarg(env);
    }
    const size_t LINE = 100;
    char buf[LINE * (size / 16 + 1)];
    size_t optr = 0;
    size_t iptr =0;
    unsigned char * bptr = (unsigned char *) ptr;

    do{
        optr += sprintf(buf + optr, "%016lx:", ptr + iptr);

        size_t old_iptr = iptr;
        for(int i = 0; i < 16 && iptr < size; ++i,++iptr){
            if(i % 2 == 0) optr += sprintf(buf + optr, " ");
            optr += sprintf(buf + optr, "%02x", bptr[iptr]);
        }
        optr += sprintf(buf + optr, "  ");
        for(int i = 0; i < 16 && old_iptr < size; ++i,++old_iptr){
            unsigned char e = bptr[old_iptr];
            optr += sprintf(buf + optr, "%c",
                            (e > 31 && e < 127)
                            ? e : '.');
        }
        optr += sprintf(buf + optr, "\n");
    }while(iptr < size);
    return enif_make_string(env, buf , ERL_NIF_LATIN1);
}

static ErlNifFunc nif_funcs[] =
{
    {"show", 2, show}
};

ERL_NIF_INIT(show_binary,nif_funcs,NULL,NULL,NULL,NULL);
