Pod::Spec.new do |s|
  s.name         = "TJDropbox"
  s.version      = "0.6"
  s.summary      = "A Dropbox v2 client library written in Objective-C"
  s.description  = "Dropbox provides a v2 SDK for iOS, but it's only compatible with Swift."

  s.homepage     = "https://github.com/timonus/TJDropbox"

  s.license      = "BSD 3-clause \"New\" or \"Revised\" License"

  s.author       = "Tim Johnsen"

  s.source       = { :git => "https://github.com/timonus/TJDropbox.git", :tag => s.version }

  s.source_files      = "TJDropbox/*.{h,m}"
  s.osx.exclude_files = "TJDropbox/TJDropboxAuthenticationViewController.{h,m}"
  s.tvos.exclude_files = "TJDropbox/TJDropboxAuthenticationViewController.{h,m}"
  s.watchos.exclude_files = "TJDropbox/TJDropboxAuthenticationViewController.{h,m}"

  s.ios.deployment_target = "8.0"
  s.osx.deployment_target = "10.9"
  s.tvos.deployment_target = "9.0"
  s.watchos.deployment_target = "2.0"
end
