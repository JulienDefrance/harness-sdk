# frozen_string_literal: true

module Strands
  module Types
    # Media-related type definitions for the SDK.
    #
    # These types represent images, documents, and videos that can be included
    # in messages. Modeled after the Bedrock API.
    module Media
      # Supported document formats
      DOCUMENT_FORMATS = %w[pdf csv doc docx xls xlsx html txt md].freeze

      # Supported image formats
      IMAGE_FORMATS = %w[png jpeg gif webp].freeze

      # Supported video formats
      VIDEO_FORMATS = %w[flv mkv mov mpeg mpg mp4 three_gp webm wmv].freeze

      # A source location (generic).
      #
      # @attr type [String] the location type
      Location = Struct.new(:type, keyword_init: true)

      # An S3 storage location.
      #
      # @attr type [String] always "s3"
      # @attr uri [String] S3 URI (s3://...)
      # @attr bucket_owner [String, nil] optional account ID of bucket owner
      S3Location = Struct.new(:type, :uri, :bucket_owner, keyword_init: true) do
        def initialize(type: "s3", uri:, bucket_owner: nil)
          super(type: type, uri: uri, bucket_owner: bucket_owner)
        end
      end

      # Source for a document (bytes or location).
      #
      # @attr bytes [String, nil] binary content
      # @attr location [Location, S3Location, nil] remote location
      DocumentSource = Struct.new(:bytes, :location, keyword_init: true)

      # A document to include in a message.
      #
      # @attr format [String] document format (pdf, txt, etc.)
      # @attr name [String] document name
      # @attr source [DocumentSource] document source
      # @attr citations [Hash, nil] optional citations config
      # @attr context [String, nil] optional context
      DocumentContent = Struct.new(:format, :name, :source, :citations, :context, keyword_init: true) do
        def validate!
          raise ArgumentError, "format must be one of: #{DOCUMENT_FORMATS.join(', ')}" unless DOCUMENT_FORMATS.include?(format)

          self
        end
      end

      # Source for an image (bytes or location).
      #
      # @attr bytes [String, nil] binary content
      # @attr location [Location, S3Location, nil] remote location
      ImageSource = Struct.new(:bytes, :location, keyword_init: true)

      # An image to include in a message.
      #
      # @attr format [String] image format (png, jpeg, gif, webp)
      # @attr source [ImageSource] image source
      ImageContent = Struct.new(:format, :source, keyword_init: true) do
        def validate!
          raise ArgumentError, "format must be one of: #{IMAGE_FORMATS.join(', ')}" unless IMAGE_FORMATS.include?(format)

          self
        end
      end

      # Source for a video (bytes or location).
      #
      # @attr bytes [String, nil] binary content
      # @attr location [Location, S3Location, nil] remote location
      VideoSource = Struct.new(:bytes, :location, keyword_init: true)

      # A video to include in a message.
      #
      # @attr format [String] video format (mp4, mkv, etc.)
      # @attr source [VideoSource] video source
      VideoContent = Struct.new(:format, :source, keyword_init: true) do
        def validate!
          raise ArgumentError, "format must be one of: #{VIDEO_FORMATS.join(', ')}" unless VIDEO_FORMATS.include?(format)

          self
        end
      end
    end
  end
end
