# frozen_string_literal: true

require "base64"
require "json"
require "nokogiri"
require "pdf/reader"
require "rtesseract"
require "stringio"
require "tempfile"
require "zip"

module Markitdown
  class Converter
    TEXT_MIME_TYPES = {
      "text/plain" => :plain_text,
      "text/markdown" => :markdown,
      "text/csv" => :csv,
      "application/csv" => :csv,
      "application/json" => :json,
      "text/json" => :json,
      "application/xml" => :xml,
      "text/xml" => :xml
    }.freeze

    HTML_MIME_TYPES = ["text/html", "application/xhtml+xml"].freeze
    DOCX_MIME_TYPE = "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    PDF_MIME_TYPE = "application/pdf"

    def initialize(tesseract_path: nil)
      @tesseract_path = tesseract_path || find_executable("tesseract")
    end

    def convert_pages(pages)
      converted_pages = Array(pages).map.with_index { |page, index| convert_page(stringify_keys(page), index) }
      markdown = converted_pages.map { |page| page[:markdown].to_s.strip }.reject(&:empty?).join("\n\n").strip
      warnings = converted_pages.flat_map { |page| page[:warnings] }

      Result.new(
        markdown: markdown,
        warnings: warnings,
        metadata: {
          "gem" => "markitdown",
          "version" => VERSION,
          "page_count" => converted_pages.length,
          "sources" => converted_pages.map { |page| page[:metadata] },
          "warnings" => warnings
        }
      )
    end

    private

    attr_reader :tesseract_path

    def convert_page(page, index)
      mime_type = normalized_mime_type(page)
      name = page["name"].to_s.strip
      name = "page-#{index + 1}" if name.empty?
      bytes = decode_page(page.fetch("base64", ""))
      strategy = TEXT_MIME_TYPES[mime_type]

      markdown =
        if strategy
          send(:"#{strategy}_to_markdown", bytes)
        elsif HTML_MIME_TYPES.include?(mime_type)
          html_to_markdown(bytes)
        elsif mime_type == PDF_MIME_TYPE
          pdf_to_markdown(bytes)
        elsif mime_type == DOCX_MIME_TYPE
          docx_to_markdown(bytes)
        elsif mime_type.start_with?("image/")
          image_to_markdown(bytes, mime_type)
        else
          raise ConversionError, "Unsupported MIME type for Markdown conversion: #{mime_type}"
        end

      {
        markdown: page_section(name, markdown),
        warnings: [],
        metadata: page_metadata(index, name, mime_type, bytes.bytesize)
      }
    rescue ConversionError => e
      {
        markdown: "",
        warnings: ["#{name}: #{e.message}"],
        metadata: page_metadata(index, name, mime_type, bytes&.bytesize.to_i, e.message)
      }
    end

    def plain_text_to_markdown(bytes)
      scrub_utf8(bytes)
    end

    def markdown_to_markdown(bytes)
      scrub_utf8(bytes)
    end

    def csv_to_markdown(bytes)
      "```csv\n#{scrub_utf8(bytes).strip}\n```"
    end

    def json_to_markdown(bytes)
      text = scrub_utf8(bytes).strip
      parsed = JSON.parse(text)
      "```json\n#{JSON.pretty_generate(parsed)}\n```"
    rescue JSON::ParserError
      "```json\n#{text}\n```"
    end

    def xml_to_markdown(bytes)
      "```xml\n#{scrub_utf8(bytes).strip}\n```"
    end

    def html_to_markdown(bytes)
      fragment = Nokogiri::HTML.fragment(scrub_utf8(bytes))
      fragment.css("script, style").remove
      markdown_nodes(fragment.children).join("\n\n").gsub(/\n{3,}/, "\n\n").strip
    end

    def pdf_to_markdown(bytes)
      reader = PDF::Reader.new(StringIO.new(bytes))
      reader.pages.each_with_index.filter_map do |page, index|
        text = page.text.to_s.gsub(/[ \t]+/, " ").strip
        next if text.empty?

        "<!-- page #{index + 1} -->\n\n#{text}"
      end.join("\n\n").tap do |markdown|
        raise ConversionError, "PDF did not contain extractable text" if markdown.strip.empty?
      end
    rescue PDF::Reader::MalformedPDFError, PDF::Reader::UnsupportedFeatureError => e
      raise ConversionError, "PDF conversion failed: #{e.message}"
    end

    def docx_to_markdown(bytes)
      xml = nil
      Zip::File.open_buffer(StringIO.new(bytes)) do |zip|
        entry = zip.find_entry("word/document.xml")
        raise ConversionError, "DOCX document.xml was not found" unless entry

        xml = entry.get_input_stream.read
      end

      document = Nokogiri::XML(xml)
      document.remove_namespaces!
      paragraphs = document.xpath("//p").filter_map do |paragraph|
        text = paragraph.xpath(".//t").map(&:text).join.strip
        text unless text.empty?
      end
      markdown = paragraphs.join("\n\n").strip
      raise ConversionError, "DOCX did not contain extractable text" if markdown.empty?

      markdown
    rescue Zip::Error => e
      raise ConversionError, "DOCX conversion failed: #{e.message}"
    end

    def image_to_markdown(bytes, mime_type)
      raise ConversionError, "Tesseract is required for local image OCR" if tesseract_path.to_s.empty?

      Tempfile.create(["markitdown", extension_for(mime_type)]) do |file|
        file.binmode
        file.write(bytes)
        file.flush
        output = RTesseract.new(file.path, command: tesseract_path).to_s.strip
        raise ConversionError, "Image OCR returned no text" if output.empty?

        output
      end
    rescue Errno::ENOENT
      raise ConversionError, "Tesseract executable was not found"
    end

    def markdown_nodes(nodes)
      nodes.flat_map do |node|
        case node.name
        when "h1"
          "# #{node.text.strip}"
        when "h2"
          "## #{node.text.strip}"
        when "h3"
          "### #{node.text.strip}"
        when "h4"
          "#### #{node.text.strip}"
        when "h5"
          "##### #{node.text.strip}"
        when "h6"
          "###### #{node.text.strip}"
        when "p", "div", "section", "article", "header", "footer", "main"
          markdown_nodes(node.children)
        when "br"
          "\n"
        when "ul"
          node.css("> li").map { |item| "- #{inline_text(item).strip}" }
        when "ol"
          node.css("> li").map.with_index(1) { |item, item_index| "#{item_index}. #{inline_text(item).strip}" }
        when "table"
          table_to_markdown(node)
        when "text"
          text = node.text.strip
          text unless text.empty?
        else
          if node.children.any?
            markdown_nodes(node.children)
          else
            text = node.text.strip
            text unless text.empty?
          end
        end
      end.flatten.compact.reject { |value| value.to_s.strip.empty? }
    end

    def table_to_markdown(table)
      rows = table.css("tr").map do |row|
        row.css("th,td").map { |cell| inline_text(cell).gsub(/\s+/, " ").strip }
      end.reject(&:empty?)
      return [] if rows.empty?

      header = rows.first
      separator = Array.new(header.length, "---")
      body = rows.drop(1)

      [
        "| #{header.join(" | ")} |",
        "| #{separator.join(" | ")} |",
        *body.map { |row| "| #{row.join(" | ")} |" }
      ].join("\n")
    end

    def inline_text(node)
      node.text.gsub(/\s+/, " ").strip
    end

    def page_section(name, markdown)
      body = markdown.to_s.strip
      raise ConversionError, "Conversion produced empty Markdown" if body.empty?

      "## #{escape_heading(name)}\n\n#{body}"
    end

    def page_metadata(index, name, mime_type, byte_size, warning = nil)
      {
        "index" => index,
        "name" => name,
        "mime_type" => mime_type,
        "byte_size" => byte_size,
        "warning" => warning
      }.compact
    end

    def normalized_mime_type(page)
      mime_type = page["mime_type"].to_s.strip
      mime_type = page["mimeType"].to_s.strip if mime_type.empty?
      mime_type.empty? ? "application/octet-stream" : mime_type
    end

    def decode_page(base64)
      raise ConversionError, "Document data is missing" if base64.to_s.empty?

      Base64.strict_decode64(base64.to_s)
    rescue ArgumentError
      raise ConversionError, "Document data is not valid base64"
    end

    def scrub_utf8(bytes)
      bytes.to_s.force_encoding(Encoding::UTF_8).scrub.strip
    end

    def escape_heading(value)
      value.to_s.gsub(/\s+/, " ").strip.gsub("#", "\\#")
    end

    def stringify_keys(value)
      value.to_h.each_with_object({}) { |(key, item), hash| hash[key.to_s] = item }
    end

    def extension_for(mime_type)
      case mime_type
      when "image/jpeg"
        ".jpg"
      when "image/png"
        ".png"
      when "image/webp"
        ".webp"
      when "image/tiff"
        ".tiff"
      else
        ""
      end
    end

    def find_executable(name)
      ENV["PATH"].to_s.split(File::PATH_SEPARATOR).map { |path| File.join(path, name) }.find { |path| File.executable?(path) }
    end
  end
end
