# Run after xcodebuild: ruby Scripts/check-app-icon.rb [path/to/Tracklet.app]
require 'json'
require 'digest'
require 'open3'

root = File.expand_path('..', __dir__)
app = ARGV.first || File.join(root, '.build/xcode/Build/Products/Debug/Tracklet.app')

%w[Light Dark].each do |appearance|
  name = "Tracklet Logo #{appearance}.png"
  original = File.join(root, 'Resources/images', name)
  packaged = File.join(root, 'Resources/AppIcon.icon/Assets', name)
  abort "Artwork differs from original: #{appearance}" unless Digest::SHA256.file(original) == Digest::SHA256.file(packaged)
end

[app, File.join(app, 'Contents/PlugIns/TrackletWidgetExtension.appex')].each do |bundle|
  resources = File.join(bundle, 'Contents/Resources')
  info, status = Open3.capture2('plutil', '-convert', 'json', '-o', '-', File.join(bundle, 'Contents/Info.plist'))
  abort "Icon not configured: #{bundle}" unless status.success? && JSON.parse(info)['CFBundleIconName'] == 'AppIcon'
  abort "Legacy icon missing: #{bundle}" unless File.binread(File.join(resources, 'AppIcon.icns'), 4) == 'icns'

  assets, status = Open3.capture2('assetutil', '--info', File.join(resources, 'Assets.car'))
  abort "Cannot inspect compiled assets: #{bundle}" unless status.success?
  stacks = JSON.parse(assets).select { |asset| asset['Name'] == 'AppIcon' && asset['AssetType'] == 'IconImageStack' }
  %w[NSAppearanceNameAqua NSAppearanceNameDarkAqua].each do |appearance|
    abort "Missing compiled appearance #{appearance}: #{bundle}" unless stacks.any? { |asset| asset['Appearance'] == appearance }
  end
end
puts 'PASS: original artwork preserved; app AND widget contain light/dark and legacy icons.'
