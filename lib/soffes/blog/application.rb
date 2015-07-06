require 'sinatra'
require 'redis'
require 'json'

module Soffes
  module Blog
    class Application < Sinatra::Application
      PAGE_SIZE = 3
      WEBHOOK_SECRET = ENV['WEBHOOK_SECRET'].freeze

      post '/_/import' do
        content_type :json
        unless params[:secret] == WEBHOOK_SECRET
          return { error: 'Invalid secret.' }.to_json
        end

        require 'soffes/blog/importer'
        count = Soffes::Blog::Importer.new.import
        { imported: count }.to_json
      end

      get '/sitemap.xml' do
        posts = []
        (1..PostsController.total_pages).each do |page|
          posts += PostsController.posts(page)
        end
        content_type :xml
        erb :sitemap, locals: { posts: posts }, layout: nil
      end

      get %r{/$|/(\d+)$} do |page|
        page = (page || 1).to_i

        erb :index, locals: {
          posts: PostsController.posts(page),
          page: page,
          total_pages: PostsController.total_pages
        }
      end

      get %r{/([\w\d\-]+)$} do |key|
        post = PostsController.post(key)
        return erb :not_found unless post

        erb :show, locals: {
          post: post,
          newer_post: PostsController.newer_post(key),
          older_post: PostsController.older_post(key)
        }
      end
    end
  end
end
