require 'ipaddr'

module Symbiosis
class IPAddr < ::IPAddr
  include Enumerable

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

  def network
    self.clone.set(@addr & @mask_addr)
  end
  
  alias max broadcast
  alias min network

  def include?(other)
    raise ArgumentError unless other.is_a?(Symbiosis::IPAddr)
    other >= self.min and other <= self.max
  end

  def each
    (self.network.to_i..self.broadcast.to_i).each do |addr|
      yield IPAddr.from_i(addr, @family)
    end
  end
  
  def <=>(other)
    @addr.to_i <=> other.to_i
  end

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

  def range_to_s
    [_to_string(@addr), _to_string(@mask_addr)].join('/')
  end

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
  
  #
  # Append the CIDR mask if there is more than on IP in the range.
  #
  def to_s
    s = [super]
    s << cidr_mask if max.to_i - min.to_i > 0
    s.join("/")
  end

end

end

