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
         "/tmp",
         "/tmp",
         },

        {
         "/srv",
         "/srv",
         },

        {
         "/srv.",
         "/srv.",
         },

        {
         "/srv/",
         "/srv/",
         },

        {
         "/srv//www.foo.com/public/htdocs",
         "/srv/foo.com/public/htdocs",
         },

        {
         "/tmp/srv",
         "/tmp/srv",
         },

        {

         "/srv/www.foo.com/public/htdocs/srv",
         "/srv/foo.com/public/htdocs/srv",
         },

        {
         "/tmp/www.foo.com/public/htdocs/srv",
         "/tmp/www.foo.com/public/htdocs/srv",
         },

        {
         "/tmp/www.foo.com/public/htdocs/srv/example.com",
         "/tmp/www.foo.com/public/htdocs/srv/example.com",
         },

        {
         "/srv/www.foo.com/public/htdocs",
         "/srv/foo.com/public/htdocs",
         },

        {
         "/srv/foo.com/public/htdocs",
         "/srv/com/public/htdocs",
         },

        {
         "/srv/.foo.com/public/htdocs",
         "/srv/foo.com/public/htdocs",
         },

        {
         "/srv/malformed-com/public/htdocs/",
         "/srv/malformed-com/public/htdocs/",
         },

        {
         "/srv/malformed-com/public/htdocs/.",
         "/srv/malformed-com/public/htdocs/.",
         },

        {
         "/srv/malformed-com/public/htdocs/.x",
         "/srv/x",
         },

        /* This test is expected to only strip the first prefix. */
        {
         "/srv/bar.bar.foo.com/public/htdocs",
         "/srv/bar.foo.com/public/htdocs",
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
