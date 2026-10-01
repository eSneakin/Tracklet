# Run after xcodebuild: ruby Scripts/check-app-icon.rb [path/to/Tracklet.app]
require 'json'
require 'digest'
require 'open3'

root = File.expand_path('..', __dir__)
app = ARGV.first || File.join(root, '.build/xcode/Build/Products/Debug/Tracklet.app')
resources = File.join(app, 'Contents/Resources')

%w[Light Dark].each do |appearance|
  name = "Tracklet Logo #{appearance}.png"
  original = File.join(root, 'Resources/images', name)
  packaged = File.join(root, 'Resources/AppIcon.icon/Assets', name)
  abort "Artwork differs from original: #{appearance}" unless Digest::SHA256.file(original) == Digest::SHA256.file(packaged)
end

info, status = Open3.capture2('plutil', '-convert', 'json', '-o', '-', File.join(app, 'Contents/Info.plist'))
abort 'App icon not configured' unless status.success? && JSON.parse(info)['CFBundleIconName'] == 'AppIcon'
abort 'Legacy icon missing' unless File.binread(File.join(resources, 'AppIcon.icns'), 4) == 'icns'

assets, status = Open3.capture2('assetutil', '--info', File.join(resources, 'Assets.car'))
abort 'Cannot inspect compiled assets' unless status.success?
stacks = JSON.parse(assets).select { |asset| asset['Name'] == 'AppIcon' && asset['AssetType'] == 'IconImageStack' }
%w[NSAppearanceNameAqua NSAppearanceNameDarkAqua].each do |appearance|
  abort "Missing compiled appearance: #{appearance}" unless stacks.any? { |asset| asset['Appearance'] == appearance }
end
puts 'PASS: original artwork preserved, light/dark compiled, legacy icon present.'
