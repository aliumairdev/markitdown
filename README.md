# Markitdown

Markitdown is a local Ruby document-to-Markdown converter for AI ingestion.
It is inspired by Microsoft MarkItDown, but implemented as a Ruby gem.

The rule is strict: this gem converts files locally first. AI services should
receive the resulting Markdown, not raw document pages, for analysis.

## Supported Inputs

- Plain text and Markdown
- HTML
- CSV, JSON, and XML
- PDFs with embedded text
- DOCX files
- Images through local Tesseract OCR, when the `tesseract` executable is installed

Scanned PDFs and images require local OCR tooling. If OCR is unavailable or a
file cannot be converted locally, the result includes warnings and empty
Markdown instead of calling an AI fallback.

## Usage

```ruby
result = Markitdown.convert_pages([
  {
    "base64" => Base64.strict_encode64(File.binread("document.pdf")),
    "mime_type" => "application/pdf",
    "name" => "document.pdf"
  }
])

result.markdown
result.warnings
result.metadata
```

## Development

Run the gem test suite from this directory:

```bash
bundle exec rake test
```

For local app development, the gem can be used as a path dependency:

```ruby
gem "markitdown", path: "path/to/markitdown"
```

## License

MIT
