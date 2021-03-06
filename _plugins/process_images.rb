require 'addressable/uri'
require 'base64'
require 'mini_magick'
require 'nokogiri'
require 'nokogiri'

module MiniMagick
  class Image
    def pixel_at(x, y)
      run_command("convert", "#{path}[1x1+#{x.to_i}+#{y.to_i}]", 'txt:').split("\n").each do |line|
        return $1 if /^0,0:.*(#[0-9a-fA-F]+)/.match(line)
      end
      nil
    end
  end
end

class ImageProcessor
  # 4.5", 4.0" (2x):            228w, 140w,  91w,  66w
  # 4.7", 5.8" (2x, 3x):        343w, 168w, 109w,  80w
  # 5.5", 6.1", 6.5" (2x, 3x):  382w, 137w, 122w,  90w
  # Deskop (1x, 2x, 3x):       1024w, 508w, 336w, 250w
  IMAGE_SIZES = [
    [
      { width: 1024, scales: [1, 2], max_width: 1024 },
      { width: 382, scales: [2, 3], max_width: 414 },
      { width: 343, scales: [2, 3], max_width: 375 },
      { width: 228, scales: [2], max_width: 320 }
    ],
    [
      { width: 508, scales: [1, 2], max_width: 1024 },
      { width: 137, scales: [2, 3], max_width: 414 },
      { width: 168, scales: [2, 3], max_width: 375 },
      { width: 140, scales: [2], max_width: 320 }
    ],
    [
      { width: 336, scales: [1, 2], max_width: 1024 },
      { width: 122, scales: [2, 3], max_width: 414 },
      { width: 109, scales: [2, 3], max_width: 375 },
      { width: 91, scales: [2], max_width: 320 }
    ],
    [
      { width: 250, scales: [1, 2], max_width: 1024 },
      { width: 90, scales: [2, 3], max_width: 414 },
      { width: 80, scales: [2, 3], max_width: 375 },
      { width: 66, scales: [2], max_width: 320 }
    ]
  ].freeze

  def initialize(post)
    @post = post
    @site = post.site
  end

  def process!
    doc = Nokogiri::HTML.fragment(@post.output)
    doc.css('img').each do |node|
      next unless src = node['src']
      next if src.start_with?('http')
      next unless src.end_with?('png') || src.end_with?('jpg')

      process_image(node)
    end

    doc.css('meta[property="og:image"], meta[name="twitter:image"]').each do |node|
      url = Addressable::URI.parse(@site.config['cdn_url'])
      url.path = Addressable::URI.parse(node['content']).path
      url.query = 'w=512&dpr=2&auto=format,compress'
      node['content'] = url.to_s
    end

    @post.output = doc.to_html
  end

  private

  def process_image(node)
    src = node['src']
    url = @site.config['cdn_url'] + src
    srcset = []
    sizes = []

    is_cover = node.parent['class'] == 'cover'
    up = 1
    if node.parent.name == 'photo-row'
      count = node.parent.css('img').count
      if count > 4
        puts "Error: #{@post.data['slug']} has invalid photo-row"
      else
        up = count
      end
    end

    image_sizes = IMAGE_SIZES[up - 1]
    image_sizes.reverse.each do |size|
      # Remove this variant for covers on small phones since it gets pixelated.
      # Ideally, we'd have a separate set of image sizes just for covers, but this is fine for now.
      next if is_cover && size[:max_width] == 320

      size[:scales].reverse.each do |scale|
        srcset += ["#{url}?w=#{size[:width]}&dpr=#{scale}&auto=format,compress #{size[:width] * scale}w"]
      end

      if size[:max_width] == 1024
        sizes << '1024px'
      else
        sizes << "(max-width: #{size[:max_width]}px) #{size[:width]}px"
      end
    end


    node['src'] = "#{url}?w=1024&dpr=2&auto=format,compress"
    node['srcset'] = srcset.join(',')
    node['sizes'] = sizes.join(',')

    node['loading'] = 'lazy' unless node['loading']

    if src.end_with?('jpg')
      image = MiniMagick::Image.open(".#{src}")

      size = image.dimensions
      node['data-width'] = size[0]
      node['data-height'] = size[1]

      if ENV['RACK_ENV'] == 'production'
        if is_cover
          image.resize('4x4')
          node['style'] = "background-image:url(data:image/png;base64,#{Base64.urlsafe_encode64(image.to_blob)});background-repeat:no-repeat;background-size:cover"
        else
          image.resize('1x1')
          if color = image.pixel_at(1, 1)
            node['style'] = "background-color:#{color.downcase}"
          end
        end
      end
    end
  end
end

Jekyll::Hooks.register :posts, :post_render do |post|
  ImageProcessor.new(post).process!
end
