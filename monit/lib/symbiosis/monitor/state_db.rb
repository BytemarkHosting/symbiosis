require 'sqlite3'
require 'systemexit'

module Symbiosis
  module Monitor
    class StateDB

      VALID_STATES = %w(OK USAGEFAIL TEMPFAIL FAIL)

      #
      # For testing.
      attr_reader :dbh

      def initialize(fn = '/var/lib/symbiosis/monit.db')
        @dbh = SQLite3::Database.new(fn)

        @tbl_name = "states"
        create_table 
        @dbh.results_as_hash = true
        @dbh.type_translation = true
      end

      def table_exists?
        @dbh.get_first_value('SELECT name FROM sqlite_master WHERE type = "table" and name = ?',@tbl_name) == @tbl_name
      end

      def create_table
        sql = "CREATE TABLE IF NOT EXISTS #{@tbl_name} 
              (
                test       TEXT NOT NULL,
                exitstatus INTEGER NOT NULL,
                output     BLOB NOT NULL,
                timestamp  INTEGER NOT NULL
              )"
        @dbh.execute(sql)
        sql = "CREATE INDEX IF NOT EXISTS test_timestamp ON #{@tbl_name} (test, timestamp)" 
        @dbh.execute(sql)
      end

      def insert(test, exitstatus, output, timestamp)
        @dbh.execute("INSERT INTO #{@tbl_name}
          VALUES (?, ?, ?, ?)",
          test, exitstatus, output, timestamp.to_i
        )
      end
      
      def update(test, exitstatus, output, timestamp, last_timestamp)
        @dbh.execute("UPDATE #{@tbl_name}
          SET output = ?, timestamp = ?, exitstatus = ? 
          WHERE test = ? AND timestamp = ?", 
          output, timestamp.to_i, exitstatus, test, last_timestamp.to_i
        )
      end

      def record(test, exitstatus, output, timestamp = Time.now)
        #
        # Insert or update based on the exit status of the last result.
        #
        last = last_result_for(test)

        if last.nil? or last['exitstatus'].to_i != exitstatus
          insert(test, exitstatus, output, timestamp.to_i)
        else
          update(test, exitstatus, output, timestamp.to_i, last['timestamp'].to_i)
        end
      end

      def all_results_for(test)
        @dbh.execute("SELECT * FROM #{@tbl_name} WHERE test = ?", test)
      end

      def last_result_for(test)
        @dbh.execute("SELECT * FROM #{@tbl_name} WHERE test = ? ORDER BY timestamp DESC LIMIT 0,1", test).first
      end

      def last_success(test)
        @dbh.execute("SELECT exitstatus, output, timestamp FROM #{@tbl_name} WHERE test = ? AND exitstatus = 0 ORDER BY timestamp DESC limit 0,1", test).first
      end
      
      def last_failure(test)
        @dbh.execute("SELECT exitstatus, output, timestamp FROM #{@tbl_name} WHERE test = ? AND exitstatus != 0 ORDER BY timestamp DESC limit 0,1", test).first
      end

      def failed_since(test)
        s = last_success(test)
        t = s.nil? ? 0 : s['timestamp']
        r = @dbh.execute("SELECT timestamp FROM #{@tbl_name} WHERE test = ? AND timestamp > ? AND exitstatus != 0 ORDER BY timestamp DESC limit 0,1", test, s['timestamp']).first
        r.nil? ? nil : r['timestamp']
      end

      def cleanup(n_days = 30)
        @dbh.execute("DELETE FROM #{@tbl_name} WHERE
           (strftime('%s','now') - timestamp) > :seconds ",
          "seconds" => n_days * 24 * 3600
        )
      end

    end

  end

end


