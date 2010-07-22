/* Licensed to the Apache Software Foundation (ASF) under one or more
 * contributor license agreements.  See the NOTICE file distributed with
 * this work for additional information regarding copyright ownership.
 * The ASF licenses this file to You under the Apache License, Version 2.0
 * (the "License"); you may not use this file except in compliance with
 * the License.  You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/*
 * mod_vhost_bytemark.c: support for dynamically configured mass virtual
 * hosting for Bytemark Symbiosis.
 *
 * This software is based upon mod_vhost_alias.c, which was released under the
 * Apache licence, version 2.0.
 *
 * Copyright (c) 2008-2010 Bytemark Computer Consulting Ltd.
 * Copyright (c) 1998-1999 Demon Internet Ltd.
 *
 * mod_vhost_alias.c was submitted by Demon Internet to the Apache Software Foundation
 * in May 1999. Future revisions and derivatives of this source code
 * must acknowledge Demon Internet as the original contributor of
 * this module. All other licensing and usage conditions are those
 * of the Apache Software Foundation.
 *
 * Originally written by Tony Finch <fanf@demon.net> <dot@dotat.at>.
 *
 * Implementation ideas were taken from mod_alias.c. The overall
 * concept is derived from the OVERRIDE_DOC_ROOT/OVERRIDE_CGIDIR
 * patch to Apache 1.3b3 and a similar feature in Demon's thttpd,
 * both written by James Grinter <jrg@blodwen.demon.co.uk>.
 */

#define CORE_PRIVATE

#include "apr.h"
#include "apr_strings.h"
#include "apr_hooks.h"
#include "apr_lib.h"

#define APR_WANT_STRFUNC
#include "apr_want.h"

#include "httpd.h"
#include "http_config.h"
#include "http_core.h"
#include "http_request.h"  /* for ap_hook_translate_name */

/* steve: needed for stat() */
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>


module AP_MODULE_DECLARE_DATA vhost_bytemark_module;


/*
 * basic configuration things
 * we abbreviate "mod_vhost_alias" to "mva" for shorter names
 */

typedef enum {
    VHOST_ALIAS_UNSET, VHOST_ALIAS_NONE, VHOST_ALIAS_NAME, VHOST_ALIAS_IP
} mva_mode_e;

/*
 * Per-server module config record.
 */
typedef struct mva_sconf_t {
    const char *doc_root;
    const char *cgi_root;
    mva_mode_e doc_root_mode;
    mva_mode_e cgi_root_mode;
    int set_doc_root;
} mva_sconf_t;

static void *mva_create_server_config(apr_pool_t *p, server_rec *s)
{
    mva_sconf_t *conf;

    conf = (mva_sconf_t *) apr_pcalloc(p, sizeof(mva_sconf_t));
    conf->doc_root = NULL;
    conf->cgi_root = NULL;
    conf->doc_root_mode = VHOST_ALIAS_UNSET;
    conf->cgi_root_mode = VHOST_ALIAS_UNSET;
    conf->set_doc_root = 0;
    return conf;
}

static void *mva_merge_server_config(apr_pool_t *p, void *parentv, void *childv)
{
    mva_sconf_t *parent = (mva_sconf_t *) parentv;
    mva_sconf_t *child = (mva_sconf_t *) childv;
    mva_sconf_t *conf;

    conf = (mva_sconf_t *) apr_pcalloc(p, sizeof(*conf));
    if (child->doc_root_mode == VHOST_ALIAS_UNSET) {
        conf->doc_root_mode = parent->doc_root_mode;
        conf->doc_root = parent->doc_root;
    }
    else {
        conf->doc_root_mode = child->doc_root_mode;
        conf->doc_root = child->doc_root;
    }
    if (child->cgi_root_mode == VHOST_ALIAS_UNSET) {
        conf->cgi_root_mode = parent->cgi_root_mode;
        conf->cgi_root = parent->cgi_root;
    }
    else {
        conf->cgi_root_mode = child->cgi_root_mode;
        conf->cgi_root = child->cgi_root;
    }

    conf->set_doc_root = child->set_doc_root;
    return conf;
}


/*
 * These are just here to tell us what vhost_alias_set should do.
 * We don't put anything into them; we just use the cell addresses.
 */
static int vhost_alias_set_doc_root_ip,
    vhost_alias_set_cgi_root_ip,
    vhost_alias_set_doc_root_name,
    vhost_alias_set_cgi_root_name;

static const char *vhost_alias_set(cmd_parms *cmd, void *dummy, const char *map)
{
    mva_sconf_t *conf;
    mva_mode_e mode, *pmode;
    const char **pmap;
    const char *p;

    conf = (mva_sconf_t *) ap_get_module_config(cmd->server->module_config,
                                                &vhost_bytemark_module);
    /* there ought to be a better way of doing this */
    if (&vhost_alias_set_doc_root_ip == cmd->info) {
        mode = VHOST_ALIAS_IP;
        pmap = &conf->doc_root;
        pmode = &conf->doc_root_mode;
    }
    else if (&vhost_alias_set_cgi_root_ip == cmd->info) {
        mode = VHOST_ALIAS_IP;
        pmap = &conf->cgi_root;
        pmode = &conf->cgi_root_mode;
    }
    else if (&vhost_alias_set_doc_root_name == cmd->info) {
        mode = VHOST_ALIAS_NAME;
        pmap = &conf->doc_root;
        pmode = &conf->doc_root_mode;
    }
    else if (&vhost_alias_set_cgi_root_name == cmd->info) {
        mode = VHOST_ALIAS_NAME;
        pmap = &conf->cgi_root;
        pmode = &conf->cgi_root_mode;
    }
    else {
        return "INTERNAL ERROR: unknown command info";
    }

    if (!ap_os_is_path_absolute(cmd->pool, map)) {
        if (strcasecmp(map, "none")) {
            return "format string must be an absolute path, or 'none'";
        }
        *pmap = NULL;
        *pmode = VHOST_ALIAS_NONE;
        return NULL;
    }

    /* sanity check */
    p = map;
    while (*p != '\0') {
        if (*p++ != '%') {
            continue;
        }
        /* we just found a '%' */
        if (*p == 'p' || *p == '%') {
            ++p;
            continue;
        }
        /* optional dash */
        if (*p == '-') {
            ++p;
        }
        /* digit N */
        if (apr_isdigit(*p)) {
            ++p;
        }
        else {
            return "syntax error in format string";
        }
        /* optional plus */
        if (*p == '+') {
            ++p;
        }
        /* do we end here? */
        if (*p != '.') {
            continue;
        }
        ++p;
        /* optional dash */
        if (*p == '-') {
            ++p;
        }
        /* digit M */
        if (apr_isdigit(*p)) {
            ++p;
        }
        else {
            return "syntax error in format string";
        }
        /* optional plus */
        if (*p == '+') {
            ++p;
        }
    }
    *pmap = map;
    *pmode = mode;
    return NULL;
}


static const char *vhost_set_docroot(cmd_parms *cmd, void *dummy,
				     const char *str)
{
    mva_sconf_t *conf;
    conf = (mva_sconf_t *) ap_get_module_config(cmd->server->module_config,
						&vhost_bytemark_module);
    conf->set_doc_root = (strcasecmp(str, "yes") == 0 ||
			  strcasecmp(str, "on") == 0) ? 1 : 0;
    return NULL;
}

static const command_rec mva_commands[] =
{
    AP_INIT_TAKE1("VirtualScriptAlias", vhost_alias_set,
                  &vhost_alias_set_cgi_root_name, RSRC_CONF,
                  "how to create a ScriptAlias based on the host"),
    AP_INIT_TAKE1("VirtualDocumentRoot", vhost_alias_set,
                  &vhost_alias_set_doc_root_name, RSRC_CONF,
                  "how to create the DocumentRoot based on the host"),
    AP_INIT_TAKE1("VirtualScriptAliasIP", vhost_alias_set,
                  &vhost_alias_set_cgi_root_ip, RSRC_CONF,
                  "how to create a ScriptAlias based on the host"),
    AP_INIT_TAKE1("VirtualDocumentRootIP", vhost_alias_set,
                  &vhost_alias_set_doc_root_ip, RSRC_CONF,
                  "how to create the DocumentRoot based on the host"),
    AP_INIT_TAKE1("SetVirtualDocumentRoot", vhost_set_docroot,
		  NULL, RSRC_CONF,
	 	  "set DOCUMENT_ROOT to parsed document root"),
    { NULL }
};


/*
 * This really wants to be a nested function
 * but C is too feeble to support them.
 */
static APR_INLINE void vhost_alias_checkspace(request_rec *r, char *buf,
                                             char **pdest, int size)
{
    /* XXX: what if size > HUGE_STRING_LEN? */
    if (*pdest + size > buf + HUGE_STRING_LEN) {
        **pdest = '\0';
        if (r->filename) {
            r->filename = apr_pstrcat(r->pool, r->filename, buf, NULL);
        }
        else {
            r->filename = apr_pstrdup(r->pool, buf);
        }
        *pdest = buf;
    }
}

static void vhost_alias_interpolate(request_rec *r, mva_sconf_t *conf,
				    const char *name, const char *map,
				    const char *uri)
{
    /* 0..9 9..0 */
    enum { MAXDOTS = 19 };
    const char *dots[MAXDOTS+1];
    int ndots;

    char buf[HUGE_STRING_LEN];
    char *dest, last;

    int N, M, Np, Mp, Nd, Md;
    const char *start, *end;

    const char *p;

    ndots = 0;
    dots[ndots++] = name-1; /* slightly naughty */
    for (p = name; *p; ++p){
        if (*p == '.' && ndots < MAXDOTS) {
            dots[ndots++] = p;
        }
    }
    dots[ndots] = p;

    r->filename = NULL;

    dest = buf;
    last = '\0';
    while (*map) {
        if (*map != '%') {
            /* normal characters */
            vhost_alias_checkspace(r, buf, &dest, 1);
            last = *dest++ = *map++;
            continue;
        }
        /* we are in a format specifier */
        ++map;
        /* can't be a slash */
        last = '\0';
        /* %% -> % */
        if (*map == '%') {
            ++map;
            vhost_alias_checkspace(r, buf, &dest, 1);
            *dest++ = '%';
            continue;
        }
        /* port number */
        if (*map == 'p') {
            ++map;
            /* no. of decimal digits in a short plus one */
            vhost_alias_checkspace(r, buf, &dest, 7);
            dest += apr_snprintf(dest, 7, "%d", ap_get_server_port(r));
            continue;
        }
        /* deal with %-N+.-M+ -- syntax is already checked */
        N = M = 0;   /* value */
        Np = Mp = 0; /* is there a plus? */
        Nd = Md = 0; /* is there a dash? */
        if (*map == '-') ++map, Nd = 1;
        N = *map++ - '0';
        if (*map == '+') ++map, Np = 1;
        if (*map == '.') {
            ++map;
            if (*map == '-') {
                ++map, Md = 1;
            }
            M = *map++ - '0';
            if (*map == '+') {
                ++map, Mp = 1;
            }
        }
        /* note that N and M are one-based indices, not zero-based */
        start = dots[0]+1; /* ptr to the first character */
        end = dots[ndots]; /* ptr to the character after the last one */
        if (N != 0) {
            if (N > ndots) {
                start = "_";
                end = start+1;
            }
            else if (!Nd) {
                start = dots[N-1]+1;
                if (!Np) {
                    end = dots[N];
                }
            }
            else {
                if (!Np) {
                    start = dots[ndots-N]+1;
                }
                end = dots[ndots-N+1];
            }
        }
        if (M != 0) {
            if (M > end - start) {
                start = "_";
                end = start+1;
            }
            else if (!Md) {
                start = start+M-1;
                if (!Mp) {
                    end = start+1;
                }
            }
            else {
                if (!Mp) {
                    start = end-M;
                }
                end = end-M+1;
            }
        }
        vhost_alias_checkspace(r, buf, &dest, end - start);
        for (p = start; p < end; ++p) {
            *dest++ = apr_tolower(*p);
        }
    }
    *dest = '\0';
    /* no double slashes */
    if (last == '/') {
        ++uri;
    }

    if (r->filename) {
        r->filename = apr_pstrcat(r->pool, r->filename, buf, uri, NULL);
    }
    else {
        r->filename = apr_pstrcat(r->pool, buf, uri, NULL);
    }

    /*
     * Steve: remove "www." prefix after /srv  if the named
     * path doesn't exist.
     *
     *  This means that a request for www.foo.com & foo.com may both be
     * handled via /srv/foo.com/public/htdocs/.
     *
     *  For people wishing to use a different prefix than /srv/ they should
     * update the "prefix" setting below, and things should continue to work
     * as expected.
     *
     */
    {
      struct stat buffer;

      if ( ( NULL != r ) &&
           ( NULL != r->filename ) &&
           ( stat( r->filename, &buffer ) < 0 ) ) {

        char prefix[] = "/srv";

        /* find "www." which we hope will be after /srv/ */
        char *p = strstr( r->filename, "www." );

        if ( ( p != NULL ) && ( p == r->filename + strlen(prefix) + 1 ) )  {

          /* strlen( "www." ) == 4  */
          memcpy( p ,  p +4, strlen(p) - 4 + 1) ;
        }
      }
    }

    /**
     * Set the document root for non-CGI requests.
     */
    if (conf->set_doc_root)
    {
        /* ignore cgi requests. */
        const char *cgi;

        if ( ( NULL != r ) &&
             ( NULL != r->uri ) )
          cgi = strstr(r->uri, "cgi-bin/");

        if ( NULL == cgi )
        {
            request_rec *top = (r->main)?r->main:r;
            char *tmp        = apr_pstrdup(top->pool, r->filename);
            char *p          = NULL;

            p = strstr(tmp, "/htdocs/" );
            if ( p != NULL )
              p[strlen( "/htdocs/" ) ] = '\0';

            core_server_config *core = (core_server_config *) ap_get_module_config(r->server->module_config, &core_module);

            core->ap_document_root = tmp;
        }
    }
}

static int mva_translate(request_rec *r)
{
    mva_sconf_t *conf;
    const char *name, *map, *uri;
    mva_mode_e mode;
    const char *cgi;

    conf = (mva_sconf_t *) ap_get_module_config(r->server->module_config,
                                              &vhost_bytemark_module);
    cgi = NULL;
    if (conf->cgi_root) {
        cgi = strstr(r->uri, "cgi-bin/");
        if (cgi && (cgi != r->uri + strspn(r->uri, "/"))) {
            cgi = NULL;
        }
    }
    if (cgi) {
        mode = conf->cgi_root_mode;
        map = conf->cgi_root;
        uri = cgi + strlen("cgi-bin");
    }
    else if (r->uri[0] == '/') {
        mode = conf->doc_root_mode;
        map = conf->doc_root;
        uri = r->uri;
    }
    else {
        return DECLINED;
    }

    if (mode == VHOST_ALIAS_NAME) {
        name = ap_get_server_name(r);
    }
    else if (mode == VHOST_ALIAS_IP) {
        name = r->connection->local_ip;
    }
    else {
        return DECLINED;
    }

    /* ### There is an optimization available here to determine the
     * absolute portion of the path from the server config phase,
     * through the first % segment, and note that portion of the path
     * canonical_path buffer.
     */
    r->canonical_filename = "";
    vhost_alias_interpolate(r, conf, name, map, uri);

    if (cgi) {
        /* see is_scriptaliased() in mod_cgi */
        r->handler = "cgi-script";
        apr_table_setn(r->notes, "alias-forced-type", r->handler);
    }

    return OK;
}

static void register_hooks(apr_pool_t *p)
{
    static const char * const aszPre[]={ "mod_alias.c","mod_userdir.c",NULL };

    ap_hook_translate_name(mva_translate, aszPre, NULL, APR_HOOK_MIDDLE);
}

module AP_MODULE_DECLARE_DATA vhost_bytemark_module =
{
    STANDARD20_MODULE_STUFF,
    NULL,                       /* dir config creater */
    NULL,                       /* dir merger --- default is to override */
    mva_create_server_config,   /* server config */
    mva_merge_server_config,    /* merge server configs */
    mva_commands,               /* command apr_table_t */
    register_hooks              /* register hooks */
};

