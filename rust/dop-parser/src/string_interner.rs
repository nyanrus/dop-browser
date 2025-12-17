//! Zero-copy string interning for efficient memory usage
//!
//! Strings are stored once and referenced by u32 IDs, enabling:
//! - O(1) equality checks via ID comparison
//! - Reduced memory footprint through deduplication
//! - Cache-friendly sequential access patterns

use std::collections::HashMap;
use zerocopy::{FromBytes, Immutable, IntoBytes, KnownLayout};

/// Interned string ID (1-indexed, 0 = invalid/none)
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Hash, FromBytes, IntoBytes, Immutable, KnownLayout)]
#[repr(C)]
pub struct StringId(pub u32);

impl StringId {
    pub const NONE: StringId = StringId(0);
    
    pub fn is_valid(self) -> bool {
        self.0 != 0
    }
}

/// String pool for zero-copy interning
/// 
/// Each unique string is stored once and assigned a unique u32 identifier.
pub struct StringPool {
    /// Interned string storage (1-indexed, index 0 unused)
    strings: Vec<String>,
    /// Fast string-to-ID mapping
    lookup: HashMap<String, StringId>,
}

impl Default for StringPool {
    fn default() -> Self {
        Self::new()
    }
}

impl StringPool {
    /// Create a new empty string pool
    pub fn new() -> Self {
        Self {
            strings: vec![String::new()], // Index 0 is reserved (NONE)
            lookup: HashMap::new(),
        }
    }
    
    /// Intern a string and return its unique ID
    /// 
    /// If the string already exists in the pool, returns the existing ID
    /// without allocating new storage.
    pub fn intern(&mut self, s: &str) -> StringId {
        if let Some(&id) = self.lookup.get(s) {
            return id;
        }
        
        let id = StringId(self.strings.len() as u32);
        let owned = s.to_string();
        self.lookup.insert(owned.clone(), id);
        self.strings.push(owned);
        id
    }
    
    /// Get the string associated with the given ID
    /// 
    /// Returns None if ID is out of range or is StringId::NONE
    pub fn get(&self, id: StringId) -> Option<&str> {
        if id.0 == 0 || id.0 as usize >= self.strings.len() {
            return None;
        }
        Some(&self.strings[id.0 as usize])
    }
    
    /// Look up the ID for a string without interning it
    /// 
    /// Returns None if string is not interned
    pub fn get_id(&self, s: &str) -> Option<StringId> {
        self.lookup.get(s).copied()
    }
    
    /// Get the number of interned strings (excluding NONE)
    pub fn len(&self) -> usize {
        self.strings.len() - 1
    }
    
    /// Check if the pool is empty
    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }
    
    /// Clear the pool, removing all interned strings
    pub fn clear(&mut self) {
        self.strings.truncate(1);
        self.lookup.clear();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_intern_and_retrieve() {
        let mut pool = StringPool::new();
        
        let id1 = pool.intern("hello");
        let id2 = pool.intern("world");
        let id3 = pool.intern("hello"); // Duplicate
        
        assert_eq!(id1, id3);
        assert_ne!(id1, id2);
        assert_eq!(pool.get(id1), Some("hello"));
        assert_eq!(pool.get(id2), Some("world"));
    }
    
    #[test]
    fn test_get_id() {
        let mut pool = StringPool::new();
        
        let id = pool.intern("test");
        assert_eq!(pool.get_id("test"), Some(id));
        assert_eq!(pool.get_id("nonexistent"), None);
    }
    
    #[test]
    fn test_invalid_id() {
        let pool = StringPool::new();
        assert_eq!(pool.get(StringId::NONE), None);
        assert_eq!(pool.get(StringId(999)), None);
    }
}
