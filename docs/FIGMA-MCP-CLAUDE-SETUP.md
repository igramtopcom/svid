# Figma ↔ Claude Code — MCP Bidirectional Setup Guide

> **Version**: 1.0 — March 2026
> **Purpose**: Reusable context prompt cho bất kỳ project/agent/team nào muốn setup Figma MCP với Claude Code.
> **Tác giả**: Auto-generated từ real implementation session.

---

## 1. Tổng quan kiến trúc

```
┌─────────────────────────────────────────────────────────────┐
│                      CLAUDE CODE (Terminal)                  │
│                                                             │
│  ┌─────────────────────┐     ┌───────────────────────────┐  │
│  │  figma-framelink    │     │ claude-talk-to-figma      │  │
│  │  (READ — Figma→Code)│     │ (READ+WRITE — Code→Figma) │  │
│  │  2 tools            │     │ 86 tools                  │  │
│  └────────┬────────────┘     └─────────────┬─────────────┘  │
│           │                                │                │
└───────────┼────────────────────────────────┼────────────────┘
            │ Figma REST API                 │ WebSocket :3055
            │ (via PAT token)                │
            ▼                                ▼
┌───────────────────────┐     ┌───────────────────────────────┐
│    Figma Cloud API    │     │  Figma Desktop App            │
│    (any plan works)   │     │  ┌─────────────────────────┐  │
│                       │     │  │ Claude Talk to Figma    │  │
│                       │     │  │ Plugin (WebSocket       │  │
│                       │     │  │ client ← Bun server)    │  │
│                       │     │  └─────────────────────────┘  │
└───────────────────────┘     └───────────────────────────────┘
```

### Hai chiều hoạt động

| Chiều | MCP Server | Cơ chế | Yêu cầu |
|-------|-----------|--------|----------|
| **Figma → Code** | `figma-framelink` | REST API + PAT token | Figma account (Free OK) |
| **Code → Figma** | `claude-talk-to-figma` | WebSocket qua Bun server + Figma Plugin | Figma Desktop app |

---

## 2. Prerequisites

### Bắt buộc
- **Node.js** >= 18 (`node --version`)
- **npx** (đi kèm npm)
- **Bun** runtime (`curl -fsSL https://bun.sh/install | bash`)
- **Figma account** (Free plan đủ dùng)
- **Figma Personal Access Token (PAT)**
- **Claude Code CLI** (with MCP support)

### Cho chiều Code → Figma (thêm)
- **Figma Desktop app** (không phải browser version)
- **Git** (để clone plugin repo)

### Tạo Figma PAT
1. Figma → Settings → Account → Personal access tokens
2. Tạo token mới, **tích hết tất cả scopes**
3. Expiry: **90 days** (hoặc lâu hơn)
4. Token format: `figd_xxxxxxxxxxxx`
5. **Lưu token ngay** — chỉ hiện 1 lần

---

## 3. Setup từng bước

### Bước 1: Figma-Framelink (Figma → Code)

```bash
claude mcp add --scope user figma-framelink -- \
  npx -y figma-developer-mcp \
  --figma-api-key=YOUR_FIGMA_PAT \
  --stdio
```

**Verify:**
```bash
claude mcp list
# Phải thấy: figma-framelink (stdio)
```

**Tools có sẵn (2):**
| Tool | Mô tả |
|------|--------|
| `get_figma_data` | Đọc layout, content, visuals, components từ Figma file |
| `download_figma_images` | Download SVG/PNG assets từ Figma nodes về local |

**Cách dùng:** Cung cấp Figma file URL hoặc fileKey + nodeId cho Claude.

---

### Bước 2: Clone Plugin Repo

```bash
git clone https://github.com/arinspunk/claude-talk-to-figma-mcp.git ~/claude-talk-to-figma-mcp
```

---

### Bước 3: Build WebSocket Server

```bash
cd ~/claude-talk-to-figma-mcp
npm install
npm run build
```

> **Lưu ý**: Build có thể báo DTS error (TypeScript type declarations) — **KHÔNG ảnh hưởng**. Chỉ cần JS files build thành công:
> - `dist/socket.js` — WebSocket server
> - `dist/talk_to_figma_mcp/server.js` — MCP server

---

### Bước 4: Add MCP Server cho Claude Code

```bash
claude mcp add --scope user claude-talk-to-figma -- \
  npx -p claude-talk-to-figma-mcp@latest \
  claude-talk-to-figma-mcp-server
```

---

### Bước 5: Import Plugin vào Figma Desktop

1. Mở **Figma Desktop** (bắt buộc, không phải browser)
2. Mở một file Figma bất kỳ (plugin menu chỉ có trong file, không phải Home)
3. Menu bar → **Plugins** → **Development** → **Import plugin from manifest...**
4. Navigate tới: `~/claude-talk-to-figma-mcp/src/claude_mcp_plugin/manifest.json`
5. Nếu hộp thoại không hiện path, nhấn **Cmd+Shift+G** rồi paste path

---

### Bước 6: Kết nối (mỗi session cần làm lại)

**Terminal 1 — Start WebSocket Server:**
```bash
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
cd ~/claude-talk-to-figma-mcp
bun run dist/socket.js
```
> Output: `[INFO] Claude to Figma WebSocket server running on port 3055`

**Figma Desktop — Chạy Plugin:**
1. Right-click canvas → **Plugins** → **Development** → **Claude Talk to Figma Plugin**
2. Click **"Connect"**
3. Plugin hiện: `Connected on port 3055! Copy the channel ID: XXXXXX`
4. Copy **Channel ID**

**Claude Code — Join Channel:**
```
Gọi tool: mcp__claude-talk-to-figma__join_channel với channel = "XXXXXX"
```

**Verify:**
```
Gọi tool: mcp__claude-talk-to-figma__get_document_info
→ Phải trả về document name, pages, children
```

---

## 4. Toàn bộ 88 Tools — Inventory

### A. figma-framelink (2 tools — READ)

| Tool | Params | Mô tả |
|------|--------|--------|
| `get_figma_data` | fileKey, nodeId?, depth? | Đọc toàn bộ structure, layout, styles, components |
| `download_figma_images` | fileKey, nodes[], localPath, pngScale? | Download SVG/PNG images về local |

### B. claude-talk-to-figma (86 tools — READ + WRITE)

#### Connection (1)
| Tool | Mô tả |
|------|--------|
| `join_channel` | Kết nối channel WebSocket với Figma Desktop |

#### Document & Pages (7)
| Tool | Mô tả |
|------|--------|
| `get_document_info` | Lấy thông tin document hiện tại |
| `get_pages` | Lấy danh sách pages |
| `create_page` | Tạo page mới |
| `delete_page` | Xóa page |
| `rename_page` | Đổi tên page |
| `duplicate_page` | Duplicate page |
| `set_current_page` | Chuyển sang page khác |

#### Node Inspection (4)
| Tool | Mô tả |
|------|--------|
| `get_selection` | Lấy selection hiện tại |
| `get_node_info` | Lấy chi tiết 1 node |
| `get_nodes_info` | Lấy chi tiết nhiều nodes |
| `scan_text_nodes` | Scan tất cả text nodes trong selection |

#### Shape Creation (5)
| Tool | Mô tả |
|------|--------|
| `create_rectangle` | Tạo hình chữ nhật |
| `create_ellipse` | Tạo hình ellipse |
| `create_polygon` | Tạo polygon (n sides) |
| `create_star` | Tạo hình sao |
| `create_frame` | Tạo frame container |

#### Text (14)
| Tool | Mô tả |
|------|--------|
| `create_text` | Tạo text element |
| `set_text_content` | Đổi nội dung text |
| `set_multiple_text_contents` | Đổi nhiều text cùng lúc |
| `set_font_name` | Set font family/style |
| `set_font_size` | Set font size |
| `set_font_weight` | Set font weight (100-900) |
| `set_letter_spacing` | Set letter spacing |
| `set_line_height` | Set line height |
| `set_paragraph_spacing` | Set paragraph spacing |
| `set_text_case` | Set UPPER/LOWER/TITLE |
| `set_text_decoration` | Set underline/strikethrough |
| `set_text_align` | Set text alignment |
| `get_styled_text_segments` | Lấy styled segments |
| `load_font_async` | Load font async |

#### Node Manipulation (14)
| Tool | Mô tả |
|------|--------|
| `move_node` | Di chuyển node |
| `resize_node` | Resize node |
| `rotate_node` | Xoay node |
| `clone_node` | Clone node |
| `delete_node` | Xóa node |
| `rename_node` | Đổi tên node |
| `reorder_node` | Đổi z-order (layer order) |
| `insert_child` | Chèn child vào parent |
| `group_nodes` | Group nhiều nodes |
| `ungroup_nodes` | Ungroup |
| `flatten_node` | Flatten thành path |
| `boolean_operation` | UNION/SUBTRACT/INTERSECT/EXCLUDE |
| `convert_to_frame` | Convert group → frame |
| `set_node_properties` | Set visibility/lock/opacity |

#### Appearance (6)
| Tool | Mô tả |
|------|--------|
| `set_fill_color` | Set fill (RGBA 0-1) |
| `set_stroke_color` | Set stroke color + weight |
| `set_corner_radius` | Set border radius |
| `set_effects` | Set shadows, blurs |
| `set_gradient` | Set gradient fill |
| `set_selection_colors` | Batch change colors trong selection |

#### Layout (5)
| Tool | Mô tả |
|------|--------|
| `set_auto_layout` | Config auto layout (direction, spacing, padding, wrap) |
| `set_grid` | Set layout grids |
| `get_grid` | Đọc layout grids |
| `set_guide` | Set guides |
| `get_guide` | Đọc guides |

#### Styles (3)
| Tool | Mô tả |
|------|--------|
| `get_styles` | Lấy tất cả styles |
| `set_text_style_id` | Apply text style |
| `set_effect_style_id` | Apply effect style |

#### Components (6)
| Tool | Mô tả |
|------|--------|
| `get_local_components` | Lấy local components |
| `get_remote_components` | Lấy team library components |
| `create_component_from_node` | Convert node → component |
| `create_component_instance` | Tạo instance từ component |
| `create_component_set` | Tạo component set (variants) |
| `set_instance_variant` | Đổi variant properties |

#### Images (6)
| Tool | Mô tả |
|------|--------|
| `set_image` | Set image fill từ base64 |
| `set_image_fill` | Apply image từ URL hoặc base64 |
| `replace_image_fill` | Replace image giữ transform |
| `apply_image_transform` | Adjust position/scale/rotation |
| `set_image_filters` | Apply color adjustments |
| `get_image_from_node` | Extract image metadata |

#### SVG (2)
| Tool | Mô tả |
|------|--------|
| `get_svg` | Export node → SVG string |
| `set_svg` | Import SVG string → vector node |

#### Export (1)
| Tool | Mô tả |
|------|--------|
| `export_node_as_image` | Export node → PNG/JPG/SVG/PDF |

#### Variables (4)
| Tool | Mô tả |
|------|--------|
| `get_variables` | List tất cả variable collections |
| `set_variable` | Tạo/update variable (COLOR/FLOAT/STRING/BOOLEAN) |
| `apply_variable_to_node` | Bind variable → node property |
| `switch_variable_mode` | Switch variable mode (theme) |

#### Annotations (2)
| Tool | Mô tả |
|------|--------|
| `set_annotation` | Thêm annotation label |
| `get_annotation` | Đọc annotations |

#### FigJam (6)
| Tool | Mô tả |
|------|--------|
| `create_sticky` | Tạo sticky note |
| `set_sticky_text` | Update sticky text |
| `create_shape_with_text` | Tạo shape + text (flowcharts) |
| `create_connector` | Tạo connector/arrow giữa nodes |
| `create_section` | Tạo section |
| `get_figjam_elements` | Lấy tất cả FigJam elements |

---

## 5. Workflows

### Workflow A: Code → Figma (Tạo design từ code)

```
1. Claude đọc source code (Flutter/React/Vue/etc.)
2. Claude phân tích: layout hierarchy, colors, typography, spacing, components
3. Claude dùng MCP tools để tạo Figma design:
   - create_page → create_frame (screen container)
   - create_rectangle, create_text, set_fill_color, etc.
   - set_auto_layout cho responsive layout
   - create_component_from_node cho reusable components
   - set_variable cho design tokens (colors, spacing)
4. Output: editable Figma design với proper component structure
```

**Prompt mẫu:**
```
Đọc file [path/to/screen.dart], phân tích toàn bộ UI elements,
rồi dùng claude-talk-to-figma MCP tạo design tương ứng trên Figma.
Tạo proper component hierarchy, auto-layout, và design tokens.
```

### Workflow B: Figma → Code (Tạo code từ design)

```
1. Designer cung cấp Figma file URL hoặc frame link
2. Claude dùng figma-framelink get_figma_data để đọc design
3. Claude phân tích: layout, components, styles, spacing
4. Claude generate code theo framework target (Flutter/React/etc.)
5. Output: clean, production-ready code
```

**Prompt mẫu:**
```
Dùng figma-framelink đọc design từ URL [figma-url],
rồi generate Flutter widget code matching design đó.
Sử dụng Riverpod, existing theme system, và Clean Architecture.
```

### Workflow C: Bidirectional Sync (Full loop)

```
1. Code → Figma: Claude tạo initial design từ existing code
2. Designer review + iterate trên Figma
3. Figma → Code: Claude đọc updated design, update code
4. Repeat
```

---

## 6. Lưu ý quan trọng

### Limitations
- **claude-talk-to-figma** cần Figma Desktop mở + plugin running
- **Channel ID thay đổi** mỗi lần reconnect plugin → phải join_channel lại
- **WebSocket server (Bun)** phải chạy liên tục trong background
- **figma-framelink** không tạo/sửa Figma — chỉ đọc
- **Không có Flutter→Figma trực tiếp** — Claude phải analyze code → recreate bằng MCP tools
- **Rate limit**: Figma API free plan = giới hạn requests/phút
- **Font loading**: Phải `load_font_async` trước khi tạo text với custom font

### Gotchas
- Colors trong MCP dùng **RGBA 0-1 range** (không phải 0-255)
- Auto-layout `set_auto_layout` cần apply **sau** khi tạo children
- Plugin menu chỉ hiện khi đang **trong file**, không phải Home screen
- `npm run build` có thể báo DTS error — **bỏ qua**, JS files vẫn build OK
- WebSocket server dùng **Bun** (không phải Node.js) — cài: `curl -fsSL https://bun.sh/install | bash`

### Security
- **KHÔNG commit Figma PAT** vào git
- PAT được lưu trong `~/.claude.json` (user-scoped)
- Tạo PAT với expiry hợp lý (90 days recommended)
- Nếu PAT leak → revoke ngay tại Figma Settings

---

## 7. Quick Start (Copy-paste cho project mới)

```bash
# === PREREQUISITES ===
# Cài Bun (nếu chưa có)
curl -fsSL https://bun.sh/install | bash
source ~/.zshrc  # hoặc restart terminal

# === MCP SERVER 1: Figma → Code ===
claude mcp add --scope user figma-framelink -- \
  npx -y figma-developer-mcp \
  --figma-api-key=YOUR_FIGMA_PAT \
  --stdio

# === MCP SERVER 2: Code → Figma ===
# Clone plugin repo (1 lần)
git clone https://github.com/arinspunk/claude-talk-to-figma-mcp.git ~/claude-talk-to-figma-mcp
cd ~/claude-talk-to-figma-mcp && npm install && npm run build

# Add MCP server
claude mcp add --scope user claude-talk-to-figma -- \
  npx -p claude-talk-to-figma-mcp@latest \
  claude-talk-to-figma-mcp-server

# === MỖI SESSION: Start WebSocket + Connect ===
# Terminal: start server
cd ~/claude-talk-to-figma-mcp && bun run dist/socket.js &

# Figma Desktop: run plugin → get Channel ID
# Claude Code: join_channel với Channel ID

# === VERIFY ===
# Claude Code gọi: get_document_info → phải trả về document info
```

---

## 8. Troubleshooting

| Vấn đề | Giải pháp |
|--------|-----------|
| Plugin "Disconnected from server" | Start WebSocket server: `bun run dist/socket.js` |
| "Bun is not defined" khi start server | Cài Bun: `curl -fsSL https://bun.sh/install | bash` |
| Plugin không thấy trong menu | Phải mở file Figma trước, không phải Home screen |
| DTS build error | Bỏ qua — JS files vẫn build thành công |
| Channel ID không connect | Restart plugin trong Figma, lấy Channel ID mới |
| figma-framelink 403/401 | PAT expired → tạo mới tại Figma Settings |
| "Rate limit exceeded" | Đợi 1 phút, hoặc upgrade Figma plan |
| Text không hiện font đúng | Gọi `load_font_async` trước khi tạo text |
| manifest.json not found | Re-clone: `git clone ... ~/claude-talk-to-figma-mcp` |

---

## 9. Alternative Tools (Tham khảo)

| Tool | Chiều | Ưu điểm | Hạn chế |
|------|-------|---------|---------|
| **Figma Official MCP** | Both | Official, 13 tools | Rate limit Free=6/tháng, default React output |
| **figma-mcp-write-server** | Write | 24 powerful tools | Cần setup riêng |
| **html.to.design** | HTML→Figma | Plugin Figma | Cần generate HTML trước |
| **screen.to.design** | Screenshot→Figma | Nhanh | Output = shapes, không phải components |
| **Figma Make** | AI→Figma | Built-in Figma | Chỉ generate React |
| **Figma to Code plugin** | Figma→Flutter | Free, community | Basic output |
| **Builder.io Visual Copilot** | Figma→Flutter | CLI workflow | Beta |

---

*Tài liệu này được tạo từ real implementation session. Mọi commands đã được verify trên macOS.*
