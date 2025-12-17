//! HTML Parser using html5ever
//!
//! Provides HTML5-compliant parsing with zero-copy string interning.
//! Generates a flat token tape for cache-efficient DOM construction.

use std::cell::RefCell;

use html5ever::tokenizer::{
    BufferQueue, Tag, TagKind, Token, TokenSink, TokenSinkResult, Tokenizer, TokenizerOpts,
};
use html5ever::Attribute;
use tendril::StrTendril;

use crate::string_interner::{StringId, StringPool};

/// Token type enum matching Julia's TokenType
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(u8)]
pub enum TokenType {
    StartTag = 1,
    EndTag = 2,
    Text = 3,
    Comment = 4,
    Doctype = 5,
    SelfClosing = 6,
    Attribute = 7,
}

/// A single HTML token in the tape
/// 
/// Uses interned string IDs for efficient storage and comparison.
#[derive(Clone, Copy, Debug)]
#[repr(C)]
pub struct HtmlToken {
    /// Type of the token
    pub token_type: TokenType,
    /// Interned string ID for tag/attribute name
    pub name_id: StringId,
    /// Interned string ID for value (text content, attribute value)
    pub value_id: StringId,
    /// Byte offset in original source (for error reporting)
    pub source_offset: u32,
}

impl HtmlToken {
    pub fn new(token_type: TokenType, name_id: StringId, value_id: StringId, offset: u32) -> Self {
        Self {
            token_type,
            name_id,
            value_id,
            source_offset: offset,
        }
    }
}

/// HTML tokenizer that produces a flat token tape
pub struct HtmlTokenizer {
    /// The token tape
    tokens: Vec<HtmlToken>,
    /// Shared string pool for interning
    strings: StringPool,
    /// Current source offset
    offset: u32,
}

impl Default for HtmlTokenizer {
    fn default() -> Self {
        Self::new()
    }
}

impl HtmlTokenizer {
    /// Create a new HTML tokenizer with a fresh string pool
    pub fn new() -> Self {
        Self {
            tokens: Vec::new(),
            strings: StringPool::new(),
            offset: 0,
        }
    }
    
    /// Create a new HTML tokenizer with a shared string pool
    pub fn with_pool(pool: StringPool) -> Self {
        Self {
            tokens: Vec::new(),
            strings: pool,
            offset: 0,
        }
    }
    
    /// Clear the token tape for reuse (keeps the string pool)
    pub fn reset(&mut self) {
        self.tokens.clear();
        self.offset = 0;
    }
    
    /// Get the token tape
    pub fn tokens(&self) -> &[HtmlToken] {
        &self.tokens
    }
    
    /// Get mutable access to the string pool
    pub fn strings_mut(&mut self) -> &mut StringPool {
        &mut self.strings
    }
    
    /// Get read-only access to the string pool
    pub fn strings(&self) -> &StringPool {
        &self.strings
    }
    
    /// Take ownership of the tokens and string pool
    pub fn take(self) -> (Vec<HtmlToken>, StringPool) {
        (self.tokens, self.strings)
    }
    
    /// Tokenize HTML source into a flat token tape
    pub fn tokenize(&mut self, html: &str) {
        self.reset();
        
        // Use RefCell to allow interior mutability for TokenSink
        let tokens = RefCell::new(Vec::new());
        let strings = RefCell::new(std::mem::take(&mut self.strings));
        let offset = RefCell::new(0u32);
        
        {
            let sink = TokenSinkWrapper {
                tokens: &tokens,
                strings: &strings,
                offset: &offset,
            };
            
            let tok = Tokenizer::new(sink, TokenizerOpts::default());
            let mut buffer = BufferQueue::default();
            buffer.push_back(StrTendril::from(html));
            let _ = tok.feed(&mut buffer);
            tok.end();
        }
        
        self.tokens = tokens.into_inner();
        self.strings = strings.into_inner();
        self.offset = offset.into_inner();
    }
}

/// Wrapper to implement TokenSink trait
struct TokenSinkWrapper<'a> {
    tokens: &'a RefCell<Vec<HtmlToken>>,
    strings: &'a RefCell<StringPool>,
    offset: &'a RefCell<u32>,
}

impl TokenSinkWrapper<'_> {
    fn process_tag(&self, tag: Tag) {
        let is_self_closing = tag.self_closing;
        let tag_name = tag.name.as_ref().to_lowercase();
        let tag_name_id = self.strings.borrow_mut().intern(&tag_name);
        
        let token_type = match tag.kind {
            TagKind::StartTag => {
                if is_self_closing {
                    TokenType::SelfClosing
                } else {
                    TokenType::StartTag
                }
            }
            TagKind::EndTag => TokenType::EndTag,
        };
        
        let offset = *self.offset.borrow();
        self.tokens.borrow_mut().push(HtmlToken::new(
            token_type,
            tag_name_id,
            StringId::NONE,
            offset,
        ));
        
        // Emit attribute tokens for start tags
        if matches!(tag.kind, TagKind::StartTag) {
            for attr in tag.attrs {
                self.process_attribute(attr);
            }
        }
    }
    
    fn process_attribute(&self, attr: Attribute) {
        let name = attr.name.local.as_ref().to_lowercase();
        let value = attr.value.to_string();
        
        let name_id = self.strings.borrow_mut().intern(&name);
        let value_id = if value.is_empty() {
            StringId::NONE
        } else {
            self.strings.borrow_mut().intern(&value)
        };
        
        let offset = *self.offset.borrow();
        self.tokens.borrow_mut().push(HtmlToken::new(
            TokenType::Attribute,
            name_id,
            value_id,
            offset,
        ));
    }
    
    fn process_text(&self, text: &str) {
        let trimmed = text.trim();
        if !trimmed.is_empty() {
            let text_id = self.strings.borrow_mut().intern(trimmed);
            let offset = *self.offset.borrow();
            self.tokens.borrow_mut().push(HtmlToken::new(
                TokenType::Text,
                StringId::NONE,
                text_id,
                offset,
            ));
        }
    }
    
    fn process_comment(&self, comment: &str) {
        let comment_id = self.strings.borrow_mut().intern(comment);
        let offset = *self.offset.borrow();
        self.tokens.borrow_mut().push(HtmlToken::new(
            TokenType::Comment,
            StringId::NONE,
            comment_id,
            offset,
        ));
    }
    
    fn process_doctype(&self) {
        let offset = *self.offset.borrow();
        self.tokens.borrow_mut().push(HtmlToken::new(
            TokenType::Doctype,
            StringId::NONE,
            StringId::NONE,
            offset,
        ));
    }
}

impl TokenSink for TokenSinkWrapper<'_> {
    type Handle = ();
    
    fn process_token(&self, token: Token, _line_number: u64) -> TokenSinkResult<()> {
        match token {
            Token::TagToken(tag) => {
                self.process_tag(tag);
            }
            Token::CharacterTokens(text) => {
                self.process_text(&text);
            }
            Token::CommentToken(comment) => {
                self.process_comment(&comment);
            }
            Token::DoctypeToken(_) => {
                self.process_doctype();
            }
            Token::NullCharacterToken | Token::EOFToken => {}
            Token::ParseError(_) => {}
        }
        TokenSinkResult::Continue
    }
}

/// Parse result containing tokens and string pool
pub struct ParseResult {
    pub tokens: Vec<HtmlToken>,
    pub strings: StringPool,
}

/// Convenience function to parse HTML and get results
pub fn parse_html(html: &str) -> ParseResult {
    let mut tokenizer = HtmlTokenizer::new();
    tokenizer.tokenize(html);
    let (tokens, strings) = tokenizer.take();
    ParseResult { tokens, strings }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_basic_parsing() {
        let result = parse_html("<div><p>Hello</p></div>");
        assert!(!result.tokens.is_empty());
        
        // Should have: div start, p start, text, p end, div end
        let token_types: Vec<_> = result.tokens.iter().map(|t| t.token_type).collect();
        assert!(token_types.contains(&TokenType::StartTag));
        assert!(token_types.contains(&TokenType::EndTag));
        assert!(token_types.contains(&TokenType::Text));
    }
    
    #[test]
    fn test_attributes() {
        let result = parse_html(r#"<div id="main" class="container">Test</div>"#);
        
        // Find attribute tokens
        let attrs: Vec<_> = result.tokens.iter()
            .filter(|t| t.token_type == TokenType::Attribute)
            .collect();
        
        assert_eq!(attrs.len(), 2); // id and class
        
        // Verify attribute names are interned
        for attr in &attrs {
            let name = result.strings.get(attr.name_id).unwrap();
            assert!(name == "id" || name == "class");
        }
    }
    
    #[test]
    fn test_doctype() {
        let result = parse_html("<!DOCTYPE html><html></html>");
        
        assert!(result.tokens.iter().any(|t| t.token_type == TokenType::Doctype));
    }
    
    #[test]
    fn test_self_closing() {
        let result = parse_html("<br/><img src='test.png'/>");
        
        let self_closing: Vec<_> = result.tokens.iter()
            .filter(|t| t.token_type == TokenType::SelfClosing)
            .collect();
        
        assert_eq!(self_closing.len(), 2);
    }
    
    #[test]
    fn test_comment() {
        let result = parse_html("<!-- This is a comment --><div></div>");
        
        assert!(result.tokens.iter().any(|t| t.token_type == TokenType::Comment));
    }
}
