require 'pp'

module StackProf
  class Report
    def initialize(data)
      @data = data

      frames = {}
      @data[:frames].each{ |k,v| frames[k.to_s] = v }
      @data[:frames] = frames
    end

    def frames(sort_by_total=false)
      Hash[ *@data[:frames].sort_by{ |iseq, stats| -stats[sort_by_total ? :total_samples : :samples] }.flatten(1) ]
    end

    def overall_samples
      @data[:samples]
    end

    def max_samples
      @data[:max_samples] ||= frames.max_by{ |addr, frame| frame[:samples] }.last[:samples]
    end

    def files
      @data[:files] ||= @data[:frames].inject(Hash.new) do |hash, (addr, frame)|
        if file = frame[:file] and lines = frame[:lines]
          hash[file] ||= Hash.new(0)
          lines.each do |line, num|
            hash[file][line] += num
          end
        end
        hash
      end
    end

    def print_debug
      pp @data
    end

    def print_files(f = STDOUT)
      pp files.sort_by{ |file, vals| -vals.values.inject(&:+) }
    end

    def print_graphviz(filter = nil, f = STDOUT)
      if filter
        mark_stack = []
        list = frames
        list.each{ |addr, frame| mark_stack << addr if frame[:name] =~ filter }
        while addr = mark_stack.pop
          frame = list[addr]
          unless frame[:marked]
            $stderr.puts frame[:edges].inspect
            mark_stack += frame[:edges].map{ |addr, weight| addr.to_s if list[addr.to_s][:total_samples] <= weight*1.2 }.compact if frame[:edges]
            frame[:marked] = true
          end
        end
        list = list.select{ |addr, frame| frame[:marked] }
        list.each{ |addr, frame| frame[:edges] && frame[:edges].delete_if{ |k,v| list[k.to_s].nil? } }
        list
      else
        list = frames
      end

      f.puts "digraph profile {"
      list.each do |frame, info|
        call, total = info.values_at(:samples, :total_samples)
        sample = ''
        sample << "#{call} (%2.1f%%)\\rof " % (call*100.0/overall_samples) if call < total
        sample << "#{total} (%2.1f%%)\\r" % (total*100.0/overall_samples)
        fontsize = (1.0 * call / max_samples) * 28 + 10
        size = (1.0 * total / overall_samples) * 2.0 + 0.5

        f.puts "  #{frame} [size=#{size}] [fontsize=#{fontsize}] [penwidth=\"#{size}\"] [shape=box] [label=\"#{info[:name]}\\n#{sample}\"];"
        if edges = info[:edges]
          edges.each do |edge, weight|
            size = (1.0 * weight / overall_samples) * 2.0 + 0.5
            f.puts "  #{frame} -> #{edge} [label=\"#{weight}\"] [weight=\"#{weight}\"] [penwidth=\"#{size}\"];"
          end
        end
      end
      f.puts "}"
    end

    def print_text(sort_by_total=false, f = STDOUT)
      f.printf "% 10s    (pct)  % 10s    (pct)     FRAME\n" % ["TOTAL", "SAMPLES"]
      frames(sort_by_total).each do |frame, info|
        call, total = info.values_at(:samples, :total_samples)
        f.printf "% 10d % 8s  % 10d % 8s     %s\n", total, "(%2.1f%%)" % (total*100.0/overall_samples), call, "(%2.1f%%)" % (call*100.0/overall_samples), info[:name]
      end
    end

    def print_callgrind(f = STDOUT)
      f.puts "version: 1"
      f.puts "creator: stackprof"
      f.puts "pid: 0"
      f.puts "cmd: ruby"
      f.puts "part: 1"
      f.puts "desc: mode: #{@data[:mode]}(#{@data[:interval]})"
      f.puts "desc: missed: #{@data[:missed_samples]})"
      f.puts "positions: line"
      f.puts "events: Instructions"
      f.puts "summary: #{@data[:samples]}"

      list = frames
      list.each do |addr, frame|
        f.puts "fl=#{frame[:file]}"
        f.puts "fn=#{frame[:name]}"
        frame[:lines].each do |line, weight|
          f.puts "#{line} #{weight}"
        end if frame[:lines]
        frame[:edges].each do |edge, weight|
          oframe = list[edge.to_s]
          f.puts "cfl=#{oframe[:file]}" unless oframe[:file] == frame[:file]
          f.puts "cfn=#{oframe[:name]}"
          f.puts "calls=#{weight} #{frame[:line] || 0}\n#{oframe[:line] || 0} #{weight}"
        end if frame[:edges]
        f.puts
      end

      f.puts "totals: #{@data[:samples]}"
    end

    def print_source(name, f = STDOUT)
      name = /#{Regexp.escape name}/ unless Regexp === name
      frames.each do |frame, info|
        next unless info[:name] =~ name
        file, line = info.values_at(:file, :line)
        line ||= 1

        maxline = info[:lines] ? info[:lines].keys.max : line + 5
        f.printf "%s (%s:%d)\n", info[:name], file, line

        lines = info[:lines]
        source = File.readlines(file).each_with_index do |code, i|
          next unless (line-1..maxline).include?(i)
          if lines and samples = lines[i+1]
            f.printf "% 5d % 7s / % 7s  | % 5d  | %s", samples, "(%2.1f%%" % (100.0*samples/overall_samples), "%2.1f%%)" % (100.0*samples/info[:samples]), i+1, code
          else
            f.printf "                         | % 5d  | %s", i+1, code
          end
        end
      end
    end
  end
end
