# Run after opening Tracklet and displaying its widgets: ruby Scripts/check-widget-runtime.rb [5m]
# Read-only: never unregister extensions or delete WidgetKit/Launch Services caches.
require 'open3'

interval = ARGV.fetch(0, '5m')
abort 'Use a log interval such as 2m or 1h' unless interval.match?(/\A[1-9][0-9]*[smh]\z/)

def capture!(*command)
  output, error, status = Open3.capture3(*command)
  abort "Check failed: #{command.first}: #{error}" unless status.success?
  output
end

registry = capture!('pluginkit', '-m', '-A', '-D', '-vv', '-i', 'com.tracklet.app.widget')
registered = registry.lines.map { |line| line[/^\s*Path = (.+)$/, 1] }.compact
abort 'No registered Tracklet extension' if registered.empty?
registered.each { |path| puts "Registered: #{path}" }

processes = capture!('ps', '-axo', 'comm=').lines.map(&:strip)
running = processes.select { |path| path.end_with?('/TrackletWidgetExtension.appex/Contents/MacOS/TrackletWidgetExtension') }
running.each do |executable|
  bundle = executable.delete_suffix('/Contents/MacOS/TrackletWidgetExtension')
  abort "Running extension has no bundle record: #{bundle}" unless registered.include?(bundle)
  puts "Running and registered: #{bundle}"
end
puts 'Extension currently idle; inspect timeline and logs below.' if running.empty?

directory = File.join(Dir.home, 'Library/Containers/com.tracklet.app.widget/Data/SystemData/com.apple.chrono/timelines/TrackletNowPlaying')
%w[systemSmall systemMedium systemLarge].each do |family|
  archives = Dir.glob(File.join(directory, "#{family}*.chrono-timeline")).select { |path| File.size?(path) }
  abort "No live timeline for #{family}; display this size before checking" if archives.empty?
  puts "Timeline #{family}: #{archives.map { |path| File.mtime(path) }.max}"
end

failures = capture!('/usr/bin/log', 'show', '--last', interval, '--style', 'compact', '--predicate',
                    'process == "TrackletWidgetExtension" AND eventMessage CONTAINS[c] "Fatal error"')
abort failures if failures.include?('Fatal error')
puts "PASS: live archives for all sizes; no extension fatal error in #{interval}."
puts 'Also check artwork and gallery icon visually; compiled resources alone do not prove desktop rendering.'
