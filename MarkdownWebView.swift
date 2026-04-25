import SwiftUI
import WebKit

enum MarkdownTheme { case dark, light }

struct MarkdownWebView: UIViewRepresentable {
    let markdown: String
    var theme: MarkdownTheme = .dark

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let wv = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        wv.isOpaque = false
        let bg: UIColor = theme == .dark
            ? UIColor(red: 0.024, green: 0.055, blue: 0.118, alpha: 1)
            : .white
        wv.backgroundColor = bg
        wv.scrollView.backgroundColor = bg
        wv.scrollView.showsVerticalScrollIndicator = false
        wv.scrollView.contentInset = .zero
        wv.navigationDelegate = context.coordinator
        wv.loadHTMLString(buildHTML(markdown, theme: theme), baseURL: nil)
        return wv
    }

    func updateUIView(_ wv: WKWebView, context: Context) {
        guard context.coordinator.lastMarkdown != markdown else { return }
        context.coordinator.lastMarkdown = markdown
        wv.loadHTMLString(buildHTML(markdown, theme: theme), baseURL: nil)
    }

    // MARK: - HTML builders

    static func buildPrintHTML(_ md: String) -> String {
        buildHTML(md, theme: .light)
    }

    static func buildHTML(_ md: String, theme: MarkdownTheme) -> String {
        let css = theme == .dark ? darkCSS : lightCSS

        // Escape markdown for safe embedding as a JS string literal
        let jsonStr = md
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
            .replacingOccurrences(of: "<", with: "\\u003C")
            .replacingOccurrences(of: ">", with: "\\u003E")

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <style>\(css)</style>
        </head>
        <body>
        <div id="md"></div>
        <script>
        (function(){
          var raw = "\(jsonStr)";

          function esc(t){
            return t.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
          }

          function inline(t){
            t = esc(t);
            t = t.replace(/!\\[([^\\]]*)\\]\\(([^)]+)\\)/g,'<img src="$2" alt="$1">');
            t = t.replace(/`([^`]+)`/g,'<code>$1</code>');
            t = t.replace(/\\*\\*\\*(.+?)\\*\\*\\*/g,'<strong><em>$1</em></strong>');
            t = t.replace(/\\*\\*(.+?)\\*\\*/g,'<strong>$1</strong>');
            t = t.replace(/__(.+?)__/g,'<strong>$1</strong>');
            t = t.replace(/\\*([^*\\n]+)\\*/g,'<em>$1</em>');
            t = t.replace(/_([^_\\n]+)_/g,'<em>$1</em>');
            t = t.replace(/~~(.+?)~~/g,'<del>$1</del>');
            t = t.replace(/\\[([^\\]]+)\\]\\(([^)]+)\\)/g,'<a href="$2">$1</a>');
            return t;
          }

          function isSep(line){
            var s = line.trim();
            return s.indexOf('|')>=0 && s.indexOf('-')>=0 && /^[|:\\- \\t]+$/.test(s);
          }

          function splitRow(s){
            s = s.trim();
            if(s.charAt(0)==='|') s=s.slice(1);
            if(s.charAt(s.length-1)==='|') s=s.slice(0,-1);
            return s.split('|').map(function(c){return c.trim();});
          }

          var lines = raw.replace(/\\r\\n/g,'\\n').replace(/\\r/g,'\\n').split('\\n');
          var html='', i=0, inUL=false, inOL=false;

          function closeList(){
            if(inUL){html+='</ul>';inUL=false;}
            if(inOL){html+='</ol>';inOL=false;}
          }

          while(i<lines.length){
            var raw_line=lines[i], trim=raw_line.trim();

            // Code block
            if(trim.indexOf('```')===0){
              closeList();
              var lang=trim.slice(3).trim();
              var cls=lang?' class="language-'+lang+'"':'';
              var code=[];i++;
              while(i<lines.length && lines[i].trim().indexOf('```')!==0){code.push(lines[i]);i++;}
              html+='<pre><code'+cls+'>'+esc(code.join('\\n'))+'</code></pre>';
              i++;continue;
            }

            // Table
            if(trim.indexOf('|')>=0 && i+1<lines.length && isSep(lines[i+1])){
              closeList();
              var hdrs=splitRow(trim); i+=2;
              html+='<div class="table-wrap"><table><thead><tr>';
              hdrs.forEach(function(h){html+='<th>'+inline(h)+'</th>';});
              html+='</tr></thead><tbody>';
              while(i<lines.length){
                var r=lines[i].trim();
                if(!r||r.indexOf('|')<0)break;
                var cells=splitRow(r);
                html+='<tr>';
                for(var j=0;j<hdrs.length;j++){
                  html+='<td>'+inline(j<cells.length?cells[j]:'')+'</td>';
                }
                html+='</tr>';i++;
              }
              html+='</tbody></table></div>';continue;
            }

            // Raw HTML line (e.g. <img>, <div>, etc.) — pass through without escaping
            if(trim.charAt(0)==='<'){closeList();html+=trim;i++;continue;}

            // HR
            if(trim==='---'||trim==='***'||trim==='___'){closeList();html+='<hr>';i++;continue;}

            // Headers
            if(trim.indexOf('#### ')===0){closeList();html+='<h4>'+inline(trim.slice(5))+'</h4>';}
            else if(trim.indexOf('### ')===0){closeList();html+='<h3>'+inline(trim.slice(4))+'</h3>';}
            else if(trim.indexOf('## ')===0){closeList();html+='<h2>'+inline(trim.slice(3))+'</h2>';}
            else if(trim.indexOf('# ')===0){closeList();html+='<h1>'+inline(trim.slice(2))+'</h1>';}
            else if(trim.indexOf('> ')===0){closeList();html+='<blockquote>'+inline(trim.slice(2))+'</blockquote>';}
            else if(trim.indexOf('- ')===0||trim.indexOf('* ')===0||trim.indexOf('+ ')===0){
              if(inOL){html+='</ol>';inOL=false;}
              if(!inUL){html+='<ul>';inUL=true;}
              html+='<li>'+inline(trim.slice(2))+'</li>';
            }
            else if(/^\\d+\\.\\s/.test(trim)){
              if(inUL){html+='</ul>';inUL=false;}
              if(!inOL){html+='<ol>';inOL=true;}
              html+='<li>'+inline(trim.replace(/^\\d+\\.\\s/,''))+'</li>';
            }
            else if(!trim){closeList();html+='<div class="gap"></div>';}
            else{closeList();html+='<p>'+inline(trim)+'</p>';}

            i++;
          }
          closeList();
          document.getElementById('md').innerHTML=html;
        })();
        </script>
        </body>
        </html>
        """
    }

    // Called from UIViewRepresentable (instance context)
    private func buildHTML(_ md: String, theme: MarkdownTheme) -> String {
        MarkdownWebView.buildHTML(md, theme: theme)
    }

    // MARK: - CSS themes

    private static let darkCSS = """
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            background: #060e1e;
            color: rgba(255,255,255,0.87);
            font-family: -apple-system, 'SF Pro Text', sans-serif;
            font-size: 15px;
            line-height: 1.75;
            padding: 18px 20px 36px 20px;
            -webkit-text-size-adjust: none;
        }
        .gap { height: 0.55em; }
        h1,h2,h3,h4 { color:#fff; font-weight:800; margin-top:1.3em; margin-bottom:0.35em; line-height:1.2; }
        h1 { font-size:1.75em; }
        h2 { font-size:1.35em; border-bottom:1px solid rgba(59,130,246,0.25); padding-bottom:0.3em; }
        h3 { font-size:1.1em; color:rgba(255,255,255,0.9); }
        h4 { font-size:0.97em; color:rgba(255,255,255,0.75); font-weight:700; }
        p  { margin:0.5em 0; }
        strong { color:#fff; font-weight:700; }
        em     { color:rgba(255,255,255,0.75); font-style:italic; }
        del    { color:rgba(255,255,255,0.38); }
        code {
            font-family:'SF Mono',Menlo,monospace; font-size:0.86em;
            background:rgba(34,211,238,0.10); color:#22d3ee;
            padding:2px 6px; border-radius:5px;
        }
        pre {
            background:#070f1e; border:1px solid rgba(59,130,246,0.28);
            border-radius:12px; padding:14px 16px; overflow-x:auto; margin:0.9em 0;
        }
        pre code { background:none; color:rgba(255,255,255,0.82); padding:0; font-size:0.84em; line-height:1.65; }
        blockquote {
            border-left:3px solid #22d3ee; margin:0.7em 0; padding:7px 14px;
            background:rgba(34,211,238,0.06); border-radius:0 10px 10px 0;
            color:rgba(255,255,255,0.6); font-style:italic;
        }
        ul,ol { padding-left:1.5em; margin:0.5em 0; }
        li { margin:0.28em 0; }
        li::marker { color:#22d3ee; }
        hr { border:none; border-top:1px solid rgba(255,255,255,0.1); margin:1.1em 0; }
        a  { color:#22d3ee; text-decoration:none; }
        a:active { opacity:0.7; }
        .table-wrap { overflow-x:auto; margin:0.9em 0; border-radius:12px; }
        table { width:100%; border-collapse:collapse; font-size:0.9em; }
        th,td { padding:9px 13px; text-align:left; border-bottom:1px solid rgba(255,255,255,0.08); }
        th { background:rgba(59,130,246,0.18); color:#fff; font-weight:700; font-size:0.85em;
             text-transform:uppercase; letter-spacing:0.04em; border-bottom:1px solid rgba(59,130,246,0.4); }
        tr:nth-child(even) td { background:rgba(255,255,255,0.03); }
        tr:last-child td { border-bottom:none; }
        img { max-width:100%; height:auto; border-radius:10px; margin:0.6em 0; display:block; }
    """

    private static let lightCSS = """
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            background: #ffffff;
            color: #1a1a1a;
            font-family: -apple-system, 'SF Pro Text', Georgia, serif;
            font-size: 15px;
            line-height: 1.8;
            padding: 24px 28px 48px 28px;
            -webkit-text-size-adjust: none;
        }
        .gap { height: 0.6em; }
        h1,h2,h3,h4 { color:#111; font-weight:800; margin-top:1.4em; margin-bottom:0.4em; line-height:1.2; }
        h1 { font-size:1.8em; border-bottom:2px solid #e5e7eb; padding-bottom:0.3em; }
        h2 { font-size:1.35em; border-bottom:1px solid #e5e7eb; padding-bottom:0.25em; }
        h3 { font-size:1.1em; }
        h4 { font-size:0.97em; font-weight:700; color:#374151; }
        p  { margin:0.6em 0; color:#1a1a1a; }
        strong { color:#111; font-weight:700; }
        em     { font-style:italic; color:#374151; }
        del    { color:#9ca3af; }
        code {
            font-family:'SF Mono',Menlo,monospace; font-size:0.85em;
            background:#f3f4f6; color:#1d4ed8;
            padding:2px 6px; border-radius:4px;
        }
        pre {
            background:#f8fafc; border:1px solid #e2e8f0;
            border-radius:8px; padding:14px 16px; overflow-x:auto; margin:1em 0;
        }
        pre code { background:none; color:#1e293b; padding:0; font-size:0.84em; line-height:1.65; }
        blockquote {
            border-left:3px solid #3b82f6; margin:0.8em 0; padding:8px 16px;
            background:#eff6ff; border-radius:0 8px 8px 0;
            color:#374151; font-style:italic;
        }
        ul,ol { padding-left:1.6em; margin:0.6em 0; }
        li { margin:0.3em 0; color:#1a1a1a; }
        li::marker { color:#3b82f6; }
        hr { border:none; border-top:1px solid #e5e7eb; margin:1.2em 0; }
        a  { color:#2563eb; text-decoration:underline; }
        .table-wrap { overflow-x:auto; margin:1em 0; }
        table { width:100%; border-collapse:collapse; font-size:0.9em; }
        th,td { padding:9px 13px; text-align:left; border:1px solid #e5e7eb; }
        th { background:#f9fafb; color:#111; font-weight:700; font-size:0.85em; }
        tr:nth-child(even) td { background:#f9fafb; }
        img { max-width:100%; height:auto; margin:0.8em 0; display:block; }
    """

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate {
        var lastMarkdown: String = ""

        func webView(_ webView: WKWebView,
                     decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .linkActivated, let url = action.request.url {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}
