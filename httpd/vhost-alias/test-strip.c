/**
 * This is a simple driver which runs our vhost-alias transformation
 * through a number of tests.
 *
 * Steve
 * --
 */


#include <string.h>
#include <stdlib.h>
#include <stdio.h>


/**
 * For testing we use /tmp/ as a prefix.
 *
 * This is the same length as /srv/ which helps.
 */
#define _SRV_ "/tmp/"
#define VHOST_DEBUG 1



#include "mod_vhost_bytemark.h"



/**
 * This structure holds a single test case.
 *
 * The two fields have the expected values.
 */
struct test_case
{
  /**
   * The input we'll pass to the "fixup" routine.
   * NOTE: NULL is a valid input.
   */
    char *input;

  /**
   * The value we expect to receive as output.
   * NOTE: NULL is a valid (expected) output.
   */
    char *expected;
};




/**
 * Execute a single test case.
 */
int
test_directory (struct test_case input)
{

  /**
   * Work on a copy of the input - unless that input is NULL.
   */
    char *tmp = input.input;
    if (input.input != NULL)
        tmp = strdup (input.input);


  /**
   * Call the transformation function.
   */
    update_vhost_request (tmp);


  /**
   * Test the result against the expected value.
   *
   * NOTE: Take care to handle the case where
   * we expected to receive NULL.
   */
    if (((input.expected == NULL) && (tmp == NULL)) ||
        (strcmp (tmp, input.expected) == 0))
    {
        if (tmp)
            free (tmp);
        return 1;
    }


    /**
     * OK if we reach here we have a test case failure.
     */
    printf ("\n[=--------------  Test fail -----=]\n");
    printf ("received input : '%s'\n", input.input);
    printf ("expected output: '%s'\n", input.expected);
    printf ("actual   output: '%s'\n", tmp);
    printf ("[=--------------  Test fail -----=]\n");

    exit (1);
}


/**
 * Simple driver code.
 */
int
main (int argc, char *argv[])
{

  /**
   * This is our array of test cases.
   */
    struct test_case tests[] = {

        {
          "/tmp/www.foo.com/public/htdocs/index.php",
          "/tmp/foo.com/public/htdocs/index.php",
         },
        {
          "/tmp/foo.com/public/htdocs/index.php",
          "/tmp/foo.com/public/htdocs/index.php",
         },
        {
          "/bogus.php",
          "/bogus.php",
         },
        {
          "/tmp/bogus.php",
          "/tmp/bogus.php",
         },
        {
          "/tmp/a/bogus.php",
          "/tmp/a/bogus.php",
         },
        {
          "/tmp//bogus.php",
          "/tmp//bogus.php",
         },

        {
         "/tmp/bar.bar.foo.com/public/htdocs",
         "/tmp/foo.com/public/htdocs",
         },
        {
         "/tmp/.foo.com/public/htdocs",
         "/tmp/foo.com/public/htdocs",
         },
        {
         "/tmp/blog.foo.com/public/htdocs",
         "/tmp/blog.foo.com/public/htdocs",
         },
        {
         "/tmp/this.is.insane.foo.com/public/htdocs",
         "/tmp/foo.com/public/htdocs",
         },
        {
         "/tmp/1234.5.3wwwwwwwwwwwwwww.www.www.wwwwwwwwwwwwww.www.www.wwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwww.w.trash.default.skx.uk0.bigv.foo.com/public/htdocs/index.pup",
         "/tmp/foo.com/public/htdocs/index.pup",
         },

        /**
         * This transformation fails because the hostname is longer
         * than 128 characters, which is what we want.
         */
        {
         "/tmp/wwww.wwwww.wwwwww.wwwww.wwwww.wwwwwwwwwwwwwww.www.www.wwwwwwwwwwwwww.www.www.wwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwww.w.trash.default.skx.uk0.bigv.foo.com/public/htdocs/index.pup",
         "/tmp/wwww.wwwww.wwwwww.wwwww.wwwww.wwwwwwwwwwwwwww.www.www.wwwwwwwwwwwwww.www.www.wwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwww.w.trash.default.skx.uk0.bigv.foo.com/public/htdocs/index.pup",
         },


        {
         NULL,
         NULL,
         },

    };


  /**
   * Current test.
   */
    int i = 0;
    int count = sizeof (tests) / sizeof (tests[0]);

  /**
   * Test each struct.
   */
    while (i < count)
    {
        if (test_directory (tests[i]))
            printf ("[%d/%d] OK %s\n", i + 1, count, tests[i].expected);

        i++;
    }

    return 0;
}
