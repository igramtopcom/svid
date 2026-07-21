/// Shared download configuration for all engine types.
///
/// Carries optional custom HTTP headers, cookies, and proxy settings that the
/// browser media-interceptor (IDM mode) extracts at download time.  When the
/// fields are `None` the engines fall back to their existing defaults.
use std::collections::HashMap;
use reqwest::{Client, header};

/// Configuration that travels from Dart → FFI → all Rust download engines.
#[derive(Debug, Clone, Default)]
pub struct DownloadConfig {
    /// Custom User-Agent (overrides rotation when set).
    pub user_agent: Option<String>,
    /// HTTP/SOCKS proxy URL, e.g. `http://host:port` or `socks5://host:port`.
    pub proxy_url: Option<String>,
    /// Arbitrary HTTP headers forwarded from the browser session.
    /// Typical keys: `Cookie`, `Referer`, `Authorization`, `Origin`.
    pub custom_headers: HashMap<String, String>,
}

impl DownloadConfig {
    /// Build a `reqwest::Client` honouring every field in this config.
    ///
    /// Default headers (Accept, sec-fetch-*, dnt) are always set.
    /// If `custom_headers` contains a `Cookie` or `Referer` key the value is
    /// applied verbatim — the engine's auto-derived Referer and UA-rotation
    /// will NOT override keys already present in `custom_headers`.
    pub fn build_client(&self) -> Client {
        let default_ua =
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 \
             (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36";

        let ua = self
            .user_agent
            .as_deref()
            .unwrap_or(default_ua);

        let mut headers = header::HeaderMap::new();

        // Base browser-like headers
        headers.insert(
            header::USER_AGENT,
            header::HeaderValue::from_str(ua)
                .unwrap_or_else(|_| header::HeaderValue::from_static(default_ua)),
        );
        headers.insert(header::ACCEPT, header::HeaderValue::from_static("*/*"));
        headers.insert(
            header::ACCEPT_LANGUAGE,
            header::HeaderValue::from_static("en-US,en;q=0.9"),
        );
        headers.insert(
            header::HeaderName::from_static("sec-fetch-dest"),
            header::HeaderValue::from_static("empty"),
        );
        headers.insert(
            header::HeaderName::from_static("sec-fetch-mode"),
            header::HeaderValue::from_static("cors"),
        );
        headers.insert(
            header::HeaderName::from_static("sec-fetch-site"),
            header::HeaderValue::from_static("cross-site"),
        );
        headers.insert(
            header::HeaderName::from_static("dnt"),
            header::HeaderValue::from_static("1"),
        );

        // Apply custom headers (Cookie, Referer, Authorization, …)
        for (name, value) in &self.custom_headers {
            if let (Ok(hname), Ok(hval)) = (
                header::HeaderName::from_bytes(name.as_bytes()),
                header::HeaderValue::from_str(value),
            ) {
                headers.insert(hname, hval);
            }
        }

        let mut builder = Client::builder()
            .default_headers(headers)
            .connect_timeout(std::time::Duration::from_secs(15))
            .timeout(std::time::Duration::from_secs(300));

        if let Some(ref proxy) = self.proxy_url {
            if let Ok(p) = reqwest::Proxy::all(proxy.as_str()) {
                builder = builder.proxy(p);
            }
        }

        builder.build().unwrap_or_else(|_| Client::new())
    }

    /// Parse a JSON string `{"Cookie":"…","Referer":"…"}` into a HashMap.
    /// Returns an empty map on parse failure (non-fatal).
    pub fn parse_headers_json(json: &str) -> HashMap<String, String> {
        serde_json::from_str(json).unwrap_or_default()
    }

    /// Merge a raw cookie string into the custom_headers under `Cookie`.
    /// If a `Cookie` header already exists it is replaced.
    pub fn with_cookies(mut self, cookies: &str) -> Self {
        if !cookies.is_empty() {
            self.custom_headers
                .insert("Cookie".to_string(), cookies.to_string());
        }
        self
    }

    /// Returns true when the caller supplied a custom `Referer` header.
    pub fn has_custom_referer(&self) -> bool {
        self.custom_headers.contains_key("Referer")
            || self.custom_headers.contains_key("referer")
    }

    /// Returns true when the caller supplied a custom `Cookie` header.
    pub fn has_cookies(&self) -> bool {
        self.custom_headers.contains_key("Cookie")
            || self.custom_headers.contains_key("cookie")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_config_builds_client() {
        let config = DownloadConfig::default();
        let _client = config.build_client(); // should not panic
    }

    #[test]
    fn test_with_cookies() {
        let config = DownloadConfig::default()
            .with_cookies("SID=abc; HSID=xyz");
        assert!(config.has_cookies());
        assert_eq!(
            config.custom_headers.get("Cookie").unwrap(),
            "SID=abc; HSID=xyz"
        );
    }

    #[test]
    fn test_parse_headers_json_valid() {
        let json = r#"{"Cookie":"SID=abc","Referer":"https://example.com/"}"#;
        let map = DownloadConfig::parse_headers_json(json);
        assert_eq!(map.get("Cookie").unwrap(), "SID=abc");
        assert_eq!(map.get("Referer").unwrap(), "https://example.com/");
    }

    #[test]
    fn test_parse_headers_json_invalid() {
        let map = DownloadConfig::parse_headers_json("not json");
        assert!(map.is_empty());
    }

    #[test]
    fn test_has_custom_referer() {
        let mut config = DownloadConfig::default();
        assert!(!config.has_custom_referer());
        config.custom_headers.insert("Referer".to_string(), "https://x.com/".to_string());
        assert!(config.has_custom_referer());
    }

    #[test]
    fn test_custom_headers_applied_to_client() {
        let mut config = DownloadConfig::default();
        config.custom_headers.insert("Authorization".to_string(), "Bearer token123".to_string());
        let _client = config.build_client(); // should not panic
    }

    #[test]
    fn test_with_proxy() {
        let config = DownloadConfig {
            proxy_url: Some("http://proxy.example.com:8080".to_string()),
            ..Default::default()
        };
        let _client = config.build_client(); // should not panic
    }

    #[test]
    fn test_empty_cookies_not_added() {
        let config = DownloadConfig::default().with_cookies("");
        assert!(!config.has_cookies());
    }
}
