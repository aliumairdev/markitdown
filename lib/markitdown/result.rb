# frozen_string_literal: true

module Markitdown
  class Result
    attr_reader :markdown, :metadata, :warnings

    def initialize(markdown:, metadata: {}, warnings: [])
      @markdown = markdown.to_s
      @metadata = metadata
      @warnings = warnings
    end

    def markdown?
      !markdown.strip.empty?
    end
  end
end
