def show_and_do(str)
    print str.yellow
    show_wait_spinner do
      yield
    end
    puts 'Done!'.green
end
  
  class NilClass
    def blank?
      true
    end
  end
  
  class FalseClass
    def blank?
      true
    end
  end
  class TrueClass
    #   true.blank? # => false
    def blank?
      false
    end
  end
  class Array
    #   [].blank?      # => true
    #   [1,2,3].blank? # => false
    alias_method :blank?, :empty?
  end
  
  class Hash
    #   {}.blank?                # => true
    #   { key: 'value' }.blank?  # => false
    alias_method :blank?, :empty?
  end
  
  class String
    def colorize(color_code)
      "\e[#{color_code}m#{self}\e[0m"
    end
  
    def red
      colorize(31)
    end
  
    def green
      colorize(32)
    end
  
    def yellow
      colorize(33)
    end
  
    def blue
      colorize(34)
    end
  
    def pink
      colorize(35)
    end
  
    def light_blue
      colorize(36)
    end
    BLANK_RE = /\A[[:space:]]*\z/
  
    # A string is blank if it's empty or contains whitespaces only:
    #
    #   ''.blank?       # => true
    #   '   '.blank?    # => true
    #   "\t\n\r".blank? # => true
    #   ' blah '.blank? # => false
    #
    # Unicode whitespace is supported:
    #
    #   "\u00a0".blank? # => true
    #
    def blank?
      # The regexp that matches blank strings is expensive. For the case of empty
      # strings we can speed up this method (~3.5x) with an empty? call. The
      # penalty for the rest of strings is marginal.
      empty? || BLANK_RE.match?(self)
    end
  end
  
  def camelcase(str)
    str.split('-').collect(&:capitalize).join
  end
  
  def kebabcase(str)
    str.gsub(/([A-Z]+)([A-Z][a-z])/, '\1-\2').
      gsub(/([a-z\d])([A-Z])/, '\1-\2').
      tr('_', '-').
      gsub(/\s/, '-').
      gsub(/__+/, '-').
      downcase
  end
  
  def to_valid_file_name(str)
    kebabcase(str).gsub(%r{/[\x00\/\\:\*\?\"<>\|]/}, '-')
  end
  
  def yesno
    case $stdin.getch
    when 'Y', 'y' then 't'
    when 'N', 'n' then 'f'
    when 'A', 'a' then 'a'
    else
      puts 'Invalid character.'
      puts 'Type Y for yes or N for no.'
      yesno
    end
  end
  
  def clear_console
    system('cls') || system('clear')
  end
  
  def show_wait_spinner(fps = 10)
    chars = %w[| / - \\]
    delay = 1.0 / fps
    iter = 0
    spinner = Thread.new do
      while iter
        print chars[(iter += 1) % chars.length]
        sleep delay
        print "\b"
      end
    end
    yield.tap do
      iter = false
      spinner.join
    end
  end