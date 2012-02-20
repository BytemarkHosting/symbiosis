require 'sqlite3'

module Symbiosis
  module Firewall
    class BlacklistDB

      attr_reader :filename
      #
      # For testing.
      attr_reader :dbh

      def initialize(database = '/var/lib/symbiosis/firewall-blacklist.db')
        #
        # hmm.. maybe we should deal with this a bit better?
        #
        @dbh = SQLite3::Database.new(database)
        @dbh.type_translation = true
        @tbl_name = "blacklist"
        create_table
      end
      
      def set_count_for(ip, cnt, timestamp = Time.now)
        @dbh.execute("INSERT INTO #{@tbl_name}
          VALUES (?, ?, ?)",
          ip, timestamp.to_i, cnt
        )

        @count = cnt
      end

      def get_count_for(ip, timestamp = (Time.now - 48*3600))
        cnt = @dbh.execute("SELECT SUM(count) FROM #{@tbl_name} WHERE ip = ? AND timestamp >= ?", ip, timestamp.to_i).flatten.first

        return cnt.to_i
      end
      
      private
      
      #
      # Creates the SQLite table.
      #
      def create_table
        sql = "CREATE TABLE IF NOT EXISTS #{@tbl_name} 
              (
                ip         TEXT NOT NULL,
                timestamp  INTEGER NOT NULL,
                count      INTEGER NOT NULL
              )"
        @dbh.execute(sql)
      end
    end

  end

end

