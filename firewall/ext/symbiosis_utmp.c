#include <utmp.h>
#include <ruby.h>
#include <arpa/inet.h>

// Module and classes.
static VALUE mSymbiosis;
static VALUE cUtmp;

/*
 * The logic to determine if an address is IPv4 or 6 is taken from last.c in
 * sysvinit.
 *
 */
VALUE
get_ip_addr (int32_t * src)
{
  struct in_addr in4;
  struct in6_addr in6;
  unsigned int topnibble;
  unsigned int azero = 0, sitelocal = 0;
  int mapped = 0;

  char ip_dst[INET_ADDRSTRLEN];
  char ip6_dst[INET6_ADDRSTRLEN];

  /*
   * Return nil if there is no IP address
   */
  if (src[0] + src[1] + src[2] + src[3] == 0)
    return Qnil;

  /*
   *  IPv4 or IPv6 ? We use 2 heuristics:
   *  2. Current IPv6 range uses 2000-3fff or fec0-feff.
   *     Outside of that is illegal and must be IPv4.
   *  2. If last 3 bytes are 0, must be IPv4
   *  3. If IPv6 in IPv4, handle as IPv4
   *
   *  Ugly.
   */
  if (src[0] == 0 && src[1] == 0 && src[2] == htonl (0xffff))
    mapped = 1;

  topnibble = ntohl ((unsigned int) src[0]) >> 28;

  azero = ntohl ((unsigned int) src[0]) >> 16;
  sitelocal = (azero >= 0xfec0 && azero <= 0xfeff) ? 1 : 0;

  if (((topnibble < 2 || topnibble > 3) && (!sitelocal)) || mapped ||
      (src[1] == 0 && src[2] == 0 && src[3] == 0))
    {
      /* IPv4 */
      in4.s_addr = mapped ? src[3] : src[0];
      inet_ntop (AF_INET, &in4, ip_dst, INET_ADDRSTRLEN);
      return rb_str_new2 (ip_dst);
    }
  else
    {
      /* IPv6 */
      memcpy (in6.s6_addr, src, 16);
      inet_ntop (AF_INET6, &in6, ip6_dst, INET6_ADDRSTRLEN);
      return rb_str_new2 (ip6_dst);
    }
}

/*
 * Return a string or nil
 */
static VALUE
string_or_nil (char *str)
{
  if (strlen (str) == 0)
    {
      return Qnil;
    }
  else
    {
      return rb_str_new2 (str);
    }
}


/*
 * Actually read the utmp file, returning an array of hash entries.
 */

static VALUE
cUtmp_read (int argc, VALUE * argv, VALUE self)
{
  VALUE result = rb_ary_new ();
  VALUE filename;
  struct utmp *line;

  /*
   * Parse the args
   */
  rb_scan_args (argc, argv, "01", &filename);


  /*
   * Set the filename and rewind the pointer
   */
  if (TYPE (filename) == T_STRING)
    {
      utmpname (RSTRING (filename)->ptr);
    }
  else
    {
      utmpname (_PATH_WTMP);
    }

  setutent ();

  while ((line = getutent ()) != NULL)
    {

      VALUE entry = rb_hash_new ();
      /*
       * This is to create IPAddr.new below
       */
      VALUE ipaddr_args[1];

      rb_hash_aset (entry,
		    rb_str_new2("user"),
		    string_or_nil (line->ut_user));

      rb_hash_aset (entry,
		    rb_str_new2("pid"), INT2FIX (line->ut_pid));

      // Set a ruby time.
      rb_hash_aset (entry,
		    rb_str_new2("time"),
		    rb_time_new (line->ut_tv.tv_sec, line->ut_tv.tv_usec));

      rb_hash_aset (entry,
		    rb_str_new2("type"), INT2FIX (line->ut_type));

      rb_hash_aset (entry,
		    rb_str_new2("line"),
		    string_or_nil (line->ut_line));

      rb_hash_aset (entry,
		    rb_str_new2("host"),
		    string_or_nil (line->ut_host));

      ipaddr_args[0] = get_ip_addr (line->ut_addr_v6);

      if (TYPE (ipaddr_args[0]) == T_STRING)
	{
	  rb_hash_aset (entry,
			rb_str_new2("ip"),
			rb_class_new_instance (1,
					       ipaddr_args,
					       rb_const_get (rb_cObject,
							     rb_intern
							     ("IPAddr"))));
	}
      else if (TYPE (ipaddr_args[0]) == T_NIL)
	{
	  rb_hash_aset (entry, rb_str_new2("ip"), ipaddr_args[0]);
	}

      rb_ary_push (result, entry);
    }

  free (line);
  return (result);
}



// Define module, classes and methods.
void
Init_symbiosis_utmp ()
{
  mSymbiosis = rb_define_module ("Symbiosis");
  cUtmp = rb_define_class_under (mSymbiosis, "Utmp", rb_cArray);

  rb_require ("ipaddr");
  rb_define_singleton_method (cUtmp, "read", cUtmp_read, -1);
}
