require 'digest/md5'
require 'sqlite3'

module Symbiosis
  module Firewall
    class Logtail

      attr_reader :filename
      #
      # For testing.
      attr_reader :dbh

      def initialize(file, database = '/var/lib/symbiosis/firewall-logtail.db')
        #
        # hmm.. maybe we should deal with this a bit better?
        #
        raise Errno::ENOENT, file unless File.exist?(file)
        @filename = file
        @pos = nil 
        @identifier = nil
        @lines = []

        @dbh = SQLite3::Database.new(database)
        @tbl_name = "logtail"
        create_table
      end
      

      #
      # Returns the hash of the first line, or nil if no first line can be found. 
      #
      def identifier
        return @identifier unless @identifier.nil?

        line = nil
        File.open(self.filename) do |fh|
          line = fh.gets
        end

        if line.is_a?(String)
          @identifier = Digest::MD5.new.hexdigest(line)
        else
          @identifier = nil
        end

        @identifier
      end
      
      def pos=(new_pos)
        @dbh.execute("INSERT OR REPLACE INTO #{@tbl_name}
          VALUES (?, ?, ?)",
          [self.filename, self.identifier, new_pos]
        )

        @pos = new_pos
      end

      def pos
        return 0 if self.identifier.nil?
        return @pos unless @pos.nil?

        pos = @dbh.execute("SELECT pos FROM #{@tbl_name}
          WHERE filename = ? AND identifier = ? LIMIT 0,1", 
          [self.filename, self.identifier]).flatten.first

        pos = 0 if pos.nil?
        @pos = pos.to_i
      end
      
      def readlines
        return @lines unless @lines.empty?
        return @lines if self.identifier.nil?

        File.open(self.filename) do |fh|
          fh.pos = self.pos

          while !fh.eof? 
            untrusted_line = fh.gets
            if untrusted_line.respond_to?(:valid_encoding?)
              untrusted_line.force_encoding(Encoding::UTF_8)
              trusted_line = if untrusted_line.valid_encoding?
                untrusted_line
              else
                untrusted_line.force_encoding(Encoding::ASCII_8BIT).
                  encode(Encoding::UTF_8,
                    :invalid => :replace,
                    :undef => :replace,
                    :replace => '')
              end
            else
              require 'iconv'

              ic ||= Iconv.new('UTF-8//IGNORE', 'UTF-8')
              trusted_line = ic.iconv(untrusted_line + ' ')[0..-2]
            end
            @lines << trusted_line
          end

          #
          # Record the position
          #
          self.pos=fh.pos
        end

        @lines
      end

      private
      
      #
      # Creates the SQLite table.
      #
      def create_table
        sql = "CREATE TABLE IF NOT EXISTS #{@tbl_name} 
              (
                filename   TEXT NOT NULL UNIQUE,
                identifier TEXT NOT NULL,
                pos        INTEGER NOT NULL
              )"
        @dbh.execute(sql)
      end
    end

  end

end

