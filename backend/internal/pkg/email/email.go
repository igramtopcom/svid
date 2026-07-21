package email

import (
	"bytes"
	"fmt"
	"html/template"
	"net/smtp"
	"strings"

	"github.com/snakeloader/backend/internal/config"
	"github.com/snakeloader/backend/internal/pkg/logger"
)

type Service struct {
	cfg       config.EmailConfig
	templates map[string]*template.Template
}

func NewService(cfg config.EmailConfig) *Service {
	s := &Service{
		cfg:       cfg,
		templates: make(map[string]*template.Template),
	}
	s.registerTemplates()
	return s
}

func (s *Service) IsConfigured() bool {
	return s.cfg.SMTPHost != ""
}

func (s *Service) Send(to, subject, templateName string, data map[string]string) error {
	// Use brand-aware From display name when Brand is present
	from := s.cfg.From
	if brand, ok := data["Brand"]; ok && brand == "vidcombo" {
		from = "VidCombo Support <" + s.cfg.From + ">"
	} else if from != "" && !strings.Contains(from, "<") {
		from = "Svid Support <" + from + ">"
	}
	if !s.IsConfigured() {
		logger.Log.Warn().Str("to", to).Str("template", templateName).Msg("Email not sent — SMTP not configured")
		return nil
	}

	tmpl, ok := s.templates[templateName]
	if !ok {
		return fmt.Errorf("email template %q not found", templateName)
	}

	var body bytes.Buffer
	if err := tmpl.Execute(&body, data); err != nil {
		return fmt.Errorf("template execute: %w", err)
	}

	msg := fmt.Sprintf("From: %s\r\nTo: %s\r\nSubject: %s\r\nMIME-Version: 1.0\r\nContent-Type: text/html; charset=UTF-8\r\n\r\n%s",
		from, to, subject, body.String())

	auth := smtp.PlainAuth("", s.cfg.Username, s.cfg.Password, s.cfg.SMTPHost)
	addr := fmt.Sprintf("%s:%d", s.cfg.SMTPHost, s.cfg.SMTPPort)

	if err := smtp.SendMail(addr, auth, s.cfg.From, []string{to}, []byte(msg)); err != nil {
		logger.Log.Error().Err(err).Str("to", to).Msg("Failed to send email")
		return fmt.Errorf("smtp send: %w", err)
	}

	logger.Log.Info().Str("to", to).Str("template", templateName).Msg("Email sent")
	return nil
}

func (s *Service) registerTemplates() {
	s.templates["payment_confirmation"] = template.Must(template.New("payment_confirmation").Parse(`
<!DOCTYPE html>
<html>
<body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px;">
  <h2 style="color: #1a1a1a;">Payment Confirmed</h2>
  <p>Thank you for subscribing to <strong>Svid Premium</strong>!</p>
  <table style="width: 100%; border-collapse: collapse; margin: 20px 0;">
    <tr><td style="padding: 8px; border-bottom: 1px solid #eee; color: #666;">License Key</td><td style="padding: 8px; border-bottom: 1px solid #eee;"><code>{{.LicenseKey}}</code></td></tr>
    <tr><td style="padding: 8px; border-bottom: 1px solid #eee; color: #666;">Plan</td><td style="padding: 8px; border-bottom: 1px solid #eee;">{{.BillingCycle}}</td></tr>
    <tr><td style="padding: 8px; border-bottom: 1px solid #eee; color: #666;">Expires</td><td style="padding: 8px; border-bottom: 1px solid #eee;">{{.ExpiresAt}}</td></tr>
    <tr><td style="padding: 8px; color: #666;">Payment Method</td><td style="padding: 8px;">{{.PaymentMethod}}</td></tr>
  </table>
  <p style="color: #666; font-size: 14px;">Your premium features are now active across up to 3 devices.</p>
  <hr style="border: none; border-top: 1px solid #eee; margin: 20px 0;">
  <p style="color: #999; font-size: 12px;">Svid — Desktop Video Downloader<br>support@svid.app</p>
</body>
</html>`))

	s.templates["license_delivery"] = template.Must(template.New("license_delivery").Parse(`
<!DOCTYPE html>
<html>
<body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px;">
  <h2 style="color: #1a1a1a;">Your Svid Premium License</h2>
  <p>Here is your license key — keep it safe:</p>
  <div style="background: #f5f5f5; padding: 16px; border-radius: 8px; text-align: center; margin: 20px 0;">
    <code style="font-size: 18px; letter-spacing: 2px;">{{.LicenseKey}}</code>
  </div>
  <p>Enter this key in Svid → Settings → Premium to activate your subscription on any device.</p>
  <hr style="border: none; border-top: 1px solid #eee; margin: 20px 0;">
  <p style="color: #999; font-size: 12px;">Svid — Desktop Video Downloader<br>support@svid.app</p>
</body>
</html>`))

	s.templates["license_expiry_warning"] = template.Must(template.New("license_expiry_warning").Parse(`
<!DOCTYPE html>
<html>
<body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px;">
  <h2 style="color: #1a1a1a;">Your Svid Premium Expires Soon</h2>
  <p>Your Svid Premium subscription will expire in <strong>{{.DaysRemaining}} days</strong>.</p>
  <table style="width: 100%; border-collapse: collapse; margin: 20px 0;">
    <tr><td style="padding: 8px; border-bottom: 1px solid #eee; color: #666;">License Key</td><td style="padding: 8px; border-bottom: 1px solid #eee;"><code>{{.LicenseKey}}</code></td></tr>
    <tr><td style="padding: 8px; border-bottom: 1px solid #eee; color: #666;">Expires</td><td style="padding: 8px; border-bottom: 1px solid #eee;">{{.ExpiresAt}}</td></tr>
    <tr><td style="padding: 8px; color: #666;">Auto-Renew</td><td style="padding: 8px;">{{.AutoRenew}}</td></tr>
  </table>
  <p>If auto-renew is enabled, your subscription will renew automatically — no action needed.</p>
  <p>To manage your subscription or re-subscribe, visit:</p>
  <p><a href="https://svid.app" style="display: inline-block; background: #4F46E5; color: #fff; padding: 12px 24px; border-radius: 6px; text-decoration: none; font-weight: 600;">Visit Svid</a></p>
  <hr style="border: none; border-top: 1px solid #eee; margin: 20px 0;">
  <p style="color: #999; font-size: 12px;">Svid — Desktop Video Downloader<br>support@svid.app</p>
</body>
</html>`))

	s.templates["magic_link"] = template.Must(template.New("magic_link").Parse(`
<!DOCTYPE html>
<html>
<body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px;">
  <h2 style="color: #1a1a1a;">Your {{if eq .Brand "vidcombo"}}VidCombo{{else}}Svid{{end}} sign-in link</h2>
  <p>Click the button below to {{if eq .Scope "portal"}}manage your subscription{{else}}access your license{{end}}. This link expires in 10 minutes and can only be used once.</p>
  <p style="text-align: center; margin: 32px 0;">
    <a href="{{.Link}}" style="display: inline-block; background: #8D021F; color: #fff; padding: 14px 28px; border-radius: 6px; text-decoration: none; font-weight: 600;">Continue</a>
  </p>
  <p style="color: #666; font-size: 14px;">If the button doesn't work, copy this link into your browser:</p>
  <p style="color: #666; font-size: 12px; word-break: break-all;">{{.Link}}</p>
  <hr style="border: none; border-top: 1px solid #eee; margin: 20px 0;">
  <p style="color: #999; font-size: 12px;">If you didn't request this link, ignore this email. The link will expire on its own.<br>{{if eq .Brand "vidcombo"}}VidCombo{{else}}Svid{{end}} — Desktop Video Downloader<br>support@svid.app</p>
</body>
</html>`))

	s.templates["ticket_update"] = template.Must(template.New("ticket_update").Parse(`
<!DOCTYPE html>
<html>
<body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px;">
  <h2 style="color: #1a1a1a;">Support Ticket Update</h2>
  <p>Your ticket <strong>#{{.TicketID}}</strong> has been updated.</p>
  <div style="background: #f5f5f5; padding: 16px; border-radius: 8px; margin: 20px 0;">
    <p style="margin: 0;"><strong>Status:</strong> {{.Status}}</p>
    <p style="margin: 8px 0 0 0;">{{.Message}}</p>
  </div>
  <hr style="border: none; border-top: 1px solid #eee; margin: 20px 0;">
  <p style="color: #999; font-size: 12px;">Svid Support Team<br>support@svid.app</p>
</body>
</html>`))
}
