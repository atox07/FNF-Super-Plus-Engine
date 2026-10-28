package psychlua;

#if (cpp && windows)
/**
 * Parte WinAPI pura: finestre Win32 extra (layered, per-pixel alpha, click-through,
 * always-on-top, bordo opzionale) che NON rubano il focus al gioco.
 * Indipendente dalla versione di Psych. Tutte le coordinate sono in pixel dello schermo.
 *
 * Nota: "x,y,w,h" si riferiscono sempre all'AREA CLIENT (il contenuto), non alla cornice.
 * Se la finestra e' trasparente o click-through viene forzata senza bordo
 * (una finestra layered non puo' mostrare la barra del titolo).
 */
@:buildXml('
<target id="haxe">
	<lib name="user32.lib" if="windows" />
	<lib name="gdi32.lib" if="windows" />
</target>
')
@:cppFileCode('
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <vector>

struct WNWin
{
	HWND hwnd;
	int x, y, w, h;
	int adjL, adjT;
	bool borderless, topmost, transparent, clickThrough, visible;
	HDC memDC;
	HBITMAP dib;
	HBITMAP oldBmp;
	void* bits;
	int dibW, dibH;
};

static std::vector<WNWin*> g_wins;
static bool g_classRegistered = false;
static const wchar_t* WN_CLASS = L"PsychMultiWindow";

static LRESULT CALLBACK WN_Proc(HWND h, UINT m, WPARAM wp, LPARAM lp)
{
	switch (m)
	{
		case WM_CLOSE: return 0;                    // la chiusura la decide solo Lua
		case WM_MOUSEACTIVATE: return MA_NOACTIVATE; // mai rubare il focus
		case WM_ERASEBKGND: return 1;
	}
	return DefWindowProcW(h, m, wp, lp);
}

static WNWin* WN_get(int id)
{
	if (id < 1 || id > (int)g_wins.size()) return NULL;
	return g_wins[id - 1];
}

static bool WN_layered(WNWin* w) { return w->transparent || w->clickThrough; }

static void WN_apply(WNWin* w)
{
	bool layered = WN_layered(w);
	bool popup = w->borderless || layered;
	DWORD style = popup ? WS_POPUP : (WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX);
	DWORD ex = WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW;
	if (layered) ex |= WS_EX_LAYERED;
	if (w->clickThrough) ex |= WS_EX_TRANSPARENT;
	if (w->topmost) ex |= WS_EX_TOPMOST;

	SetWindowLongPtrW(w->hwnd, GWL_STYLE, (LONG_PTR)style);
	SetWindowLongPtrW(w->hwnd, GWL_EXSTYLE, (LONG_PTR)ex);

	RECT r = { 0, 0, w->w, w->h };
	AdjustWindowRectEx(&r, style, FALSE, ex);
	w->adjL = r.left;
	w->adjT = r.top;

	UINT flags = SWP_NOACTIVATE | SWP_FRAMECHANGED | (w->visible ? SWP_SHOWWINDOW : SWP_HIDEWINDOW);
	SetWindowPos(w->hwnd, w->topmost ? HWND_TOPMOST : HWND_NOTOPMOST,
		w->x + r.left, w->y + r.top, r.right - r.left, r.bottom - r.top, flags);
}

static int WN_create(const char* title, int x, int y, int w, int h)
{
	HINSTANCE inst = GetModuleHandleW(NULL);
	if (!g_classRegistered)
	{
		WNDCLASSEXW wc;
		ZeroMemory(&wc, sizeof(wc));
		wc.cbSize = sizeof(wc);
		wc.lpfnWndProc = WN_Proc;
		wc.hInstance = inst;
		wc.hCursor = LoadCursorW(NULL, MAKEINTRESOURCEW(32512));
		wc.lpszClassName = WN_CLASS;
		RegisterClassExW(&wc);
		g_classRegistered = true;
	}
	if (w < 1) w = 1;
	if (h < 1) h = 1;

	wchar_t wtitle[256];
	MultiByteToWideChar(CP_UTF8, 0, title, -1, wtitle, 256);

	HWND hwnd = CreateWindowExW(WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW | WS_EX_LAYERED, WN_CLASS, wtitle,
		WS_POPUP, x, y, w, h, NULL, NULL, inst, NULL);
	if (!hwnd) return 0;

	WNWin* win = new WNWin();
	ZeroMemory(win, sizeof(WNWin));
	win->hwnd = hwnd;
	win->x = x; win->y = y; win->w = w; win->h = h;
	win->borderless = true;
	win->topmost = true;
	win->transparent = true;
	win->clickThrough = false;
	win->visible = true;
	win->memDC = CreateCompatibleDC(NULL);
	WN_apply(win);

	for (size_t i = 0; i < g_wins.size(); i++)
	{
		if (g_wins[i] == NULL) { g_wins[i] = win; return (int)i + 1; }
	}
	g_wins.push_back(win);
	return (int)g_wins.size();
}

static void WN_destroy(int id)
{
	WNWin* w = WN_get(id);
	if (!w) return;
	if (w->dib)
	{
		SelectObject(w->memDC, w->oldBmp);
		DeleteObject(w->dib);
	}
	if (w->memDC) DeleteDC(w->memDC);
	DestroyWindow(w->hwnd);
	delete w;
	g_wins[id - 1] = NULL;
}

static void WN_setPos(int id, int x, int y)
{
	WNWin* w = WN_get(id);
	if (!w || (w->x == x && w->y == y)) return;
	w->x = x; w->y = y;
	SetWindowPos(w->hwnd, NULL, x + w->adjL, y + w->adjT, 0, 0, SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
}

static void WN_setSize(int id, int cw, int ch)
{
	WNWin* w = WN_get(id);
	if (!w) return;
	if (cw < 1) cw = 1;
	if (ch < 1) ch = 1;
	if (w->w == cw && w->h == ch) return;
	w->w = cw; w->h = ch;
	WN_apply(w);
}

static void WN_setTitle(int id, const char* title)
{
	WNWin* w = WN_get(id);
	if (!w) return;
	wchar_t wtitle[256];
	MultiByteToWideChar(CP_UTF8, 0, title, -1, wtitle, 256);
	SetWindowTextW(w->hwnd, wtitle);
}

// what: 0 borderless, 1 topmost, 2 transparent, 3 clickThrough, 4 visible
static void WN_setFlag(int id, int what, bool v)
{
	WNWin* w = WN_get(id);
	if (!w) return;
	switch (what)
	{
		case 0: w->borderless = v; break;
		case 1: w->topmost = v; break;
		case 2: w->transparent = v; break;
		case 3: w->clickThrough = v; break;
		case 4: w->visible = v; break;
	}
	WN_apply(w);
}

static void WN_ensureDib(WNWin* w, int cw, int ch)
{
	if (w->dib && w->dibW == cw && w->dibH == ch) return;
	if (w->dib)
	{
		SelectObject(w->memDC, w->oldBmp);
		DeleteObject(w->dib);
		w->dib = NULL;
	}
	BITMAPINFO bi;
	ZeroMemory(&bi, sizeof(bi));
	bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
	bi.bmiHeader.biWidth = cw;
	bi.bmiHeader.biHeight = -ch; // top-down
	bi.bmiHeader.biPlanes = 1;
	bi.bmiHeader.biBitCount = 32;
	bi.bmiHeader.biCompression = BI_RGB;
	w->dib = CreateDIBSection(w->memDC, &bi, DIB_RGB_COLORS, &w->bits, NULL, 0);
	w->oldBmp = (HBITMAP)SelectObject(w->memDC, w->dib);
	w->dibW = cw;
	w->dibH = ch;
}

// src = byte ARGB non premoltiplicati (formato di openfl BitmapData.getPixels)
static void WN_present(int id, unsigned char* src, int sw, int sh)
{
	WNWin* w = WN_get(id);
	if (!w || !src || !w->visible) return;
	if (sw != w->w || sh != w->h) return;
	WN_ensureDib(w, sw, sh);
	if (!w->bits) return;

	bool layered = WN_layered(w);
	unsigned char* d = (unsigned char*)w->bits;
	int n = sw * sh;
	for (int i = 0; i < n; i++)
	{
		unsigned int a = src[0], r = src[1], g = src[2], b = src[3];
		if (layered)
		{
			d[0] = (unsigned char)(b * a / 255);
			d[1] = (unsigned char)(g * a / 255);
			d[2] = (unsigned char)(r * a / 255);
			d[3] = (unsigned char)a;
		}
		else
		{
			d[0] = (unsigned char)b;
			d[1] = (unsigned char)g;
			d[2] = (unsigned char)r;
			d[3] = 255;
		}
		src += 4;
		d += 4;
	}

	if (layered)
	{
		POINT ptSrc = { 0, 0 };
		SIZE sz = { sw, sh };
		BLENDFUNCTION bf;
		bf.BlendOp = AC_SRC_OVER;
		bf.BlendFlags = 0;
		bf.SourceConstantAlpha = 255;
		bf.AlphaFormat = AC_SRC_ALPHA;
		UpdateLayeredWindow(w->hwnd, NULL, NULL, &sz, w->memDC, &ptSrc, 0, &bf, ULW_ALPHA);
	}
	else
	{
		HDC dc = GetDC(w->hwnd);
		BitBlt(dc, 0, 0, sw, sh, w->memDC, 0, 0, SRCCOPY);
		ReleaseDC(w->hwnd, dc);
	}
}
')
class WinNative
{
	public static function create(title:String, x:Int, y:Int, w:Int, h:Int):Int
		return untyped __cpp__('WN_create({0}.utf8_str(), {1}, {2}, {3}, {4})', title, x, y, w, h);

	public static function destroy(id:Int):Void
		untyped __cpp__('WN_destroy({0})', id);

	public static function setPos(id:Int, x:Int, y:Int):Void
		untyped __cpp__('WN_setPos({0}, {1}, {2})', id, x, y);

	public static function setSize(id:Int, w:Int, h:Int):Void
		untyped __cpp__('WN_setSize({0}, {1}, {2})', id, w, h);

	public static function setTitle(id:Int, title:String):Void
		untyped __cpp__('WN_setTitle({0}, {1}.utf8_str())', id, title);

	public static function setBorderless(id:Int, v:Bool):Void
		untyped __cpp__('WN_setFlag({0}, 0, {1})', id, v);

	public static function setAlwaysOnTop(id:Int, v:Bool):Void
		untyped __cpp__('WN_setFlag({0}, 1, {1})', id, v);

	public static function setTransparent(id:Int, v:Bool):Void
		untyped __cpp__('WN_setFlag({0}, 2, {1})', id, v);

	public static function setClickThrough(id:Int, v:Bool):Void
		untyped __cpp__('WN_setFlag({0}, 3, {1})', id, v);

	public static function setVisible(id:Int, v:Bool):Void
		untyped __cpp__('WN_setFlag({0}, 4, {1})', id, v);

	/** data = byte ARGB (openfl getPixels), lunghezza >= w*h*4 */
	public static function present(id:Int, data:haxe.io.BytesData, w:Int, h:Int):Void
	{
		if (data == null || data.length < w * h * 4)
			return;
		var p = cpp.Pointer.arrayElem(data, 0);
		untyped __cpp__('WN_present({0}, (unsigned char*){1}, {2}, {3})', id, p.raw, w, h);
	}

	public static function screenWidth():Int
		return untyped __cpp__('GetSystemMetrics(SM_CXSCREEN)');

	public static function screenHeight():Int
		return untyped __cpp__('GetSystemMetrics(SM_CYSCREEN)');
}
#end
