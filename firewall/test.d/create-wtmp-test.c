#include <string.h>
#include <stdlib.h>
#include <pwd.h>
#include <unistd.h>
#include <utmp.h>
#include <arpa/inet.h>


int
main(int argc, char *argv[])
{
  struct utmp entry;
  int addr[4];
 
  utmpname ("wtmp-test"); 
  /* rewind file */ 
  setutent();

  /* First entry */
  entry.ut_type = USER_PROCESS;
  entry.ut_pid = 1001;
  strncpy(entry.ut_line, "pts/10", UT_LINESIZE); 
  strncpy(entry.ut_id, "/10", sizeof(entry.ut_id));
  /* Fri Jul 02 08:00:00 +0100 2010 */
  entry.ut_tv.tv_sec = 1278054000;
  entry.ut_tv.tv_usec = 135790;
  strncpy(entry.ut_user, "alice", UT_NAMESIZE);
  strncpy(entry.ut_host, "office.my-brilliant-site.com", UT_HOSTSIZE);

  /* 
   * irb(main):003:0> IPAddr.new("1.2.3.4").to_i
   * => 16909060
   *
   * gotta convert that from host to network byte order.
   *
   */
  entry.ut_addr_v6[0] = htonl(16909060);
  entry.ut_addr_v6[1] = 0;
  entry.ut_addr_v6[2] = 0;
  entry.ut_addr_v6[3] = 0;
 
  pututline(&entry);

  /* 
   * Next entry -- IPv6
   *
   */
  entry.ut_type = USER_PROCESS;
  entry.ut_pid = 2001;
  strncpy(entry.ut_line, "pts/11", UT_LINESIZE); 
  strncpy(entry.ut_id, "/11", sizeof(entry.ut_id));
  /* Fri Jul 02 08:30:00 +0100 2010 */
  entry.ut_tv.tv_sec = 1278055800;
  entry.ut_tv.tv_usec = 654321;
  strncpy(entry.ut_user, "bob", UT_NAMESIZE);
  strncpy(entry.ut_host, "shop.my-brilliant-site.com", UT_HOSTSIZE);
  /*
   * 2001:ba8:dead:beef:cafe::1
   */
  entry.ut_addr_v6[0] = htonl(0x20010ba8); 
  entry.ut_addr_v6[1] = htonl(0xdeadbeef);
  entry.ut_addr_v6[2] = htonl(0xcafe0000);
  entry.ut_addr_v6[3] = htonl(0x00000001);
 
  pututline(&entry);

  /* 
   * 
   * Next -- mapped IPv6 
   *
   */
  entry.ut_type = USER_PROCESS;
  entry.ut_pid = 3001;
  strncpy(entry.ut_line, "pts/12", UT_LINESIZE); 
  strncpy(entry.ut_id, "/12", sizeof(entry.ut_id));
  /* Fri Jul 02 09:00:00 +0100 2010 */
  entry.ut_tv.tv_sec = 1278057600;
  entry.ut_tv.tv_usec = 24680;
  strncpy(entry.ut_user, "charlie", UT_NAMESIZE);
  strncpy(entry.ut_host, "garage.my-brilliant-site.com", UT_HOSTSIZE);
  /*
   * irb(main):002:0> IPAddr.new("::ffff:192.0.2.128")
   * => #<IPAddr: IPv6:0000:0000:0000:0000:0000:ffff:c000:0280/ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff>
   *
   */
  entry.ut_addr_v6[0] = htonl(0); 
  entry.ut_addr_v6[1] = htonl(0);
  entry.ut_addr_v6[2] = htonl(0x0000ffff);
  entry.ut_addr_v6[3] = htonl(0xc0000280);

  pututline(&entry);

  endutent();
  exit(EXIT_SUCCESS);
}

