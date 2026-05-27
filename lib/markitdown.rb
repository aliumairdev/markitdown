# frozen_string_literal: true

require_relative "markitdown/version"
require_relative "markitdown/conversion_error"
require_relative "markitdown/result"
require_relative "markitdown/converter"

module Markitdown
  module_function

  def convert_pages(pages, **options)
    Converter.new(**options).convert_pages(pages)
  end
end
