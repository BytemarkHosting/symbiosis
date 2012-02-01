require 'ipaddr'

module Symbiosis

#
# This class is a subclass if ::IPAddr, and adds in various useful bits.
#
class IPAddr < ::IPAddr
  include Enumerable

  #
  # Returns the broadcast address for the IP range.
  #
  def broadcast
    case @family
    when Socket::AF_INET
      @mask_addr = IN4MASK if @mask_addr > IN4MASK
      self.clone.set(self.network.to_i | ((~@mask_addr) & IN4MASK))
    when Socket::AF_INET6
      @mask_addr = IN6MASK if @mask_addr > IN6MASK
      self.clone.set(self.network.to_i | ((~@mask_addr) & IN6MASK))
    end
  end

  #
  # Returns the network address for the IP range.
  #
  def network
    self.clone.set(@addr & @mask_addr)
  end
  
  alias max broadcast
  alias min network

  #
  # Test to see if this IP range includes another.
  #
  # Raises an ArgumentError unless other is a Symbiosis::IPAddr
  #
  def include?(other)
    raise ArgumentError unless other.is_a?(Symbiosis::IPAddr)
    other >= self.min and other <= self.max
  end

  #
  # Evaluate a block for each IP address in a range.  Use with caution with IPv6 addresses!
  #
  def each
    (self.network.to_i..self.broadcast.to_i).each do |addr|
      yield IPAddr.from_i(addr, @family)
    end
  end
  
  #
  # Compare one IP with another.
  #
  def <=>(other)
    @addr.to_i <=> other.to_i
  end

  #
  # Create a new IPAddress object from an integer.  The family can be
  # Socket::AF_INET or Socket::AF_INET6.  If no family is set, then a guess is
  # made, based on the size of the integer.
  #
  def IPAddr.from_i(arg, family=nil)
    if family.nil? 
      family = (arg < 0xffffffff ? Socket::AF_INET : Socket::AF_INET6)
    end

    if Socket::AF_INET == family 
      IPAddr.new((0..3).collect{|x| x*8}.collect{|x| (arg.to_i >> x & 0xff).to_s}.reverse.join("."))

    elsif Socket::AF_INET6 == family 
      IPAddr.new((0..7).collect{|x| x*16}.collect{|x| (arg.to_i >> x & 0xffff).to_s(16)}.reverse.join(":"))

    else

      raise ArgumentError, "Unknown address family"
    end
  end

  #
  # Returns a range as address/mask_address, e.g. 1.2.3.0/255.255.255.0
  #
  def range_to_s
    [_to_string(@addr), _to_string(@mask_addr)].join('/')
  end

  #
  # Returns the CIDR mask, e.g. 24 for 1.2.3.0/24.
  #
  def cidr_mask
    #
    # Hmm.. this is a bit horrid.  But without a log2 function, there's not
    # much else we can do..
    case @family
    when Socket::AF_INET
      @mask_addr = IN4MASK if @mask_addr > IN4MASK
      n_addresses = ((~@mask_addr) & IN4MASK) + 1
      32 - (0..32).find{|m| 2**m == n_addresses}
    when Socket::AF_INET6
      @mask_addr = IN6MASK if @mask_addr > IN6MASK
      n_addresses = ((~@mask_addr) & IN6MASK) + 1
      128 - (0..128).find{|m| 2**m == n_addresses}
    end
  end

  alias prefixlen cidr_mask 
  
  #
  # Returns the address as a string, with the CIDR mask if there is more than
  # on IP in the range.
  #
  # e.g. 1.2.3.4/32 would be returned as 1.2.3.4, 2001:41c8:1:2::/64 as
  # 2001:41c8:1:2::/64.
  #
  def to_s
    s = [super]
    s << cidr_mask if max.to_i - min.to_i > 0
    s.join("/")
  end

end

end

