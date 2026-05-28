# frozen_string_literal: true

require "test_helper"
require "erb"
require "zip"

class MarkitdownConverterTest < Minitest::Test
  def test_converts_plain_text_pages_to_markdown
    result = Markitdown::Converter.new.convert_pages([
      page("Hello from a document.", "text/plain", "note.txt")
    ])

    assert_includes result.markdown, "## note.txt"
    assert_includes result.markdown, "Hello from a document."
    assert_equal "markitdown", result.metadata.fetch("gem")
  end

  def test_preserves_html_headings_lists_and_tables_as_markdown
    html = <<~HTML
      <h1>Invoice</h1>
      <ul><li>Total due</li></ul>
      <table><tr><th>Name</th><th>Amount</th></tr><tr><td>Rent</td><td>$100</td></tr></table>
    HTML

    result = Markitdown::Converter.new.convert_pages([
      page(html, "text/html", "invoice.html")
    ])

    assert_includes result.markdown, "# Invoice"
    assert_includes result.markdown, "- Total due"
    assert_includes result.markdown, "| Name | Amount |"
    assert_includes result.markdown, "| Rent | $100 |"
  end

  def test_extracts_docx_paragraph_text_locally
    result = Markitdown::Converter.new.convert_pages([
      page(docx_with_paragraphs("Lease notice", "Rent is due June 1."), Markitdown::Converter::DOCX_MIME_TYPE, "lease.docx")
    ])

    assert_includes result.markdown, "Lease notice"
    assert_includes result.markdown, "Rent is due June 1."
  end

  def test_does_not_use_ai_fallback_when_image_ocr_is_unavailable
    result = Markitdown::Converter.new(tesseract_path: nil).convert_pages([
      page("image-bytes", "image/png", "scan.png")
    ])

    assert_equal "", result.markdown
    assert_includes result.warnings.join, "Tesseract is required"
  end

  def test_uses_rtesseract_wrapper_for_image_ocr
    calls = []
    ocr = Object.new
    ocr.define_singleton_method(:to_s) { "Recognized text" }

    RTesseract.stub(:new, ->(path, options) {
      calls << [path, options]
      ocr
    }) do
      result = Markitdown::Converter.new(tesseract_path: "/usr/local/bin/tesseract").convert_pages([
        page("image-bytes", "image/png", "scan.png")
      ])

      assert_includes result.markdown, "Recognized text"
    end

    assert_equal "/usr/local/bin/tesseract", calls.dig(0, 1).fetch(:command)
    assert_match(/\.png\z/, calls.dig(0, 0))
  end

  private

  def page(content, mime_type, name)
    {
      "base64" => Base64.strict_encode64(content),
      "mime_type" => mime_type,
      "name" => name
    }
  end

  def docx_with_paragraphs(*paragraphs)
    buffer = Zip::OutputStream.write_buffer do |zip|
      zip.put_next_entry("[Content_Types].xml")
      zip.write "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"/>"

      zip.put_next_entry("word/document.xml")
      zip.write <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            #{paragraphs.map { |text| "<w:p><w:r><w:t>#{ERB::Util.html_escape(text)}</w:t></w:r></w:p>" }.join}
          </w:body>
        </w:document>
      XML
    end

    buffer.string
  end
end
