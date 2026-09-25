import Foundation

public enum TokenKind: CaseIterable {
    case comment, string, number, keyword, literal, type, attribute, function
    case meta, tag, attributeName, variable, heading, link, emphasis, inserted, deleted
}

/// A language is an ordered list of regex rules. They are compiled into one
/// alternation, so at any position the earliest-listed rule wins — comments
/// and strings are listed first so keywords inside them are left alone.
///
/// Rule patterns must not contain capturing groups; use `(?:...)`.
public struct Language: Hashable {
    public struct Rule {
        public let kind: TokenKind
        public let pattern: String
        public init(_ kind: TokenKind, _ pattern: String) {
            self.kind = kind
            self.pattern = pattern
        }
    }

    public let id: String
    public let name: String
    public let rules: [Rule]

    public var isPlainText: Bool { rules.isEmpty }

    public init(id: String, name: String, rules: [Rule]) {
        self.id = id
        self.name = name
        self.rules = rules
    }

    public static func == (lhs: Language, rhs: Language) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Detection

extension Language {
    static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mkdn", "mdwn", "mdx", "rmd"]

    public static func detect(fileName: String) -> Language {
        let lower = fileName.lowercased()
        if let language = byFileName[lower] { return language }
        if lower.hasPrefix("dockerfile") || lower.hasSuffix(".dockerfile") { return .dockerfile }
        if lower.hasPrefix(".env") { return .ini }
        let ext = (lower as NSString).pathExtension
        return byExtension[ext] ?? .plainText
    }

    static let byFileName: [String: Language] = [
        "makefile": .makefile, "gnumakefile": .makefile, "cmakelists.txt": .cmake,
        "gemfile": .ruby, "rakefile": .ruby, "podfile": .ruby, "fastfile": .ruby, "brewfile": .ruby,
        "appfile": .ruby, "vagrantfile": .ruby, "guardfile": .ruby, "dangerfile": .ruby,
        "containerfile": .dockerfile, "jenkinsfile": .groovy, "package.resolved": .json,
        ".bashrc": .shell, ".zshrc": .shell, ".profile": .shell, ".bash_profile": .shell,
        ".zprofile": .shell, ".zshenv": .shell, ".bash_aliases": .shell,
        ".gitconfig": .ini, ".gitmodules": .ini, ".editorconfig": .ini, ".npmrc": .ini,
        ".gitignore": .ignoreFile, ".dockerignore": .ignoreFile, ".gitattributes": .ignoreFile,
        ".prettierrc": .json, ".eslintrc": .json, ".babelrc": .json, ".swiftlint.yml": .yaml,
        "license": .plainText, "readme": .plainText,
    ]

    static let byExtension: [String: Language] = {
        var map: [String: Language] = [:]
        func add(_ language: Language, _ exts: String) {
            for ext in exts.split(separator: " ") { map[String(ext)] = language }
        }
        add(.swift, "swift swiftinterface")
        add(.c, "c h")
        add(.cpp, "cpp cc cxx c++ hpp hh hxx h++ ino ipp tpp cu cuh")
        add(.objc, "m mm")
        add(.csharp, "cs csx")
        add(.java, "java jav")
        add(.kotlin, "kt kts")
        add(.scala, "scala sc sbt")
        add(.groovy, "groovy gradle gvy")
        add(.go, "go")
        add(.rust, "rs")
        add(.javascript, "js mjs cjs jsx es6")
        add(.typescript, "ts tsx mts cts")
        add(.dart, "dart")
        add(.python, "py pyw pyi pyx gyp gypi")
        add(.ruby, "rb rake gemspec podspec ru erb")
        add(.php, "php phtml php3 php4 php5 phps")
        add(.shell, "sh bash zsh fish ksh csh tcsh command tool bats")
        add(.powershell, "ps1 psm1 psd1")
        add(.perl, "pl pm t pod")
        add(.lua, "lua luau rockspec")
        add(.r, "r")
        add(.sql, "sql psql mysql pgsql ddl dml")
        add(.haskell, "hs lhs purs elm")
        add(.elixir, "ex exs heex eex")
        add(.erlang, "erl hrl")
        add(.clojure, "clj cljs cljc edn")
        add(.lisp, "lisp lsp el scm ss rkt fnl")
        add(.ocaml, "ml mli fs fsi fsx re rei")
        add(.zig, "zig zon")
        add(.nim, "nim nims nimble")
        add(.julia, "jl")
        add(.html, "html htm xhtml shtml vue svelte astro hbs handlebars mustache jinja j2 liquid njk")
        add(.xml, "xml plist svg xib storyboard entitlements xcscheme xcworkspacedata csproj vbproj fsproj props targets xaml rss atom xsd xsl xslt wsdl pom resx nuspec opml kml gpx tmtheme tmlanguage")
        add(.css, "css scss sass less styl pcss")
        add(.json, "json jsonc json5 geojson har webmanifest jsonl ndjson ipynb babelrc eslintrc prettierrc code-workspace xcstrings lottie")
        add(.yaml, "yml yaml")
        add(.toml, "toml lock")
        add(.ini, "ini cfg conf properties env desktop service strings reg inf")
        add(.dockerfile, "dockerfile")
        add(.makefile, "mk mak make")
        add(.cmake, "cmake")
        add(.diff, "diff patch rej")
        add(.graphql, "graphql gql graphqls")
        add(.proto, "proto")
        add(.hcl, "tf tfvars hcl nomad")
        add(.nix, "nix")
        add(.vim, "vim vimrc")
        add(.assembly, "s asm nasm")
        add(.latex, "tex sty cls bib ltx")
        add(.markdown, "md markdown mdown mkd mdx")
        add(.solidity, "sol")
        add(.verilog, "v sv svh vh")
        add(.vhdl, "vhd vhdl")
        add(.fortran, "f f90 f95 f03 for")
        add(.pascal, "pas pp dpr lpr")
        add(.ada, "adb ads")
        add(.vb, "vb vbs bas")
        add(.batch, "bat cmd")
        add(.awk, "awk")
        add(.tcl, "tcl")
        add(.crystal, "cr")
        add(.d, "d di")
        add(.v, "vv")
        add(.odin, "odin")
        add(.gleam, "gleam")
        add(.metal, "metal")
        add(.glsl, "glsl vert frag geom comp tesc tese hlsl fx wgsl shader")
        add(.ignoreFile, "gitignore dockerignore npmignore eslintignore prettierignore")
        add(.plainText, "txt text log out csv tsv nfo me 1st")
        return map
    }()
}

// MARK: - Building blocks

enum P {
    static let dq = #""(?:[^"\\\n]|\\.)*""#
    static let sq = #"'(?:[^'\\\n]|\\.)*'"#
    static let backtick = #"`(?:[^`\\]|\\.)*`"#
    static let tripleDQ = "\"\"\"[\\s\\S]*?\"\"\""
    static let tripleSQ = #"'''[\s\S]*?'''"#
    static let slashComment = #"//.*"#
    static let blockComment = #"/\*[\s\S]*?\*/"#
    static let hashComment = #"#.*"#
    static let dashComment = #"--.*"#
    static let number = #"\b(?:0[xX][0-9a-fA-F_]+|0[bB][01_]+|0[oO][0-7_]+|\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d+)?)\w*"#
    static let call = #"\b[A-Za-z_]\w*(?=\s*\()"#
    static let capitalized = #"\b[A-Z][A-Za-z0-9_]*\b"#
    static let atAnnotation = #"@[A-Za-z_][\w.]*"#
    static let jsxTag = #"</[A-Za-z][\w.:-]*>|(?<=^|[\s(=>:?,{}])<[A-Za-z][\w.:-]*(?=[\s/>])|/>"#
    static let cPreprocessor = #"^[ \t]*#[ \t]*[a-z]+\b(?:[ \t]*<[^>\n]*>)?"#

    static func words(_ list: String, caseInsensitive: Bool = false) -> String {
        let escaped = list.split(separator: " ").map { NSRegularExpression.escapedPattern(for: String($0)) }
        let body = escaped.joined(separator: "|")
        return caseInsensitive ? #"(?i:\b(?:"# + body + #")\b)"# : #"\b(?:"# + body + #")\b"#
    }
}

extension Language {
    /// Brace languages share most of their shape.
    static func cStyle(
        _ id: String, _ name: String,
        keywords: String,
        types: String = "",
        literals: String = "true false null",
        strings: [String] = [P.dq, P.sq],
        prefix: [Rule] = [],
        extra: [Rule] = [],
        lineComment: String? = P.slashComment,
        blockComment: String? = P.blockComment,
        preprocessor: Bool = false,
        annotations: Bool = false
    ) -> Language {
        var rules: [Rule] = prefix
        if let blockComment { rules.append(Rule(.comment, blockComment)) }
        if let lineComment { rules.append(Rule(.comment, lineComment)) }
        rules += strings.map { Rule(.string, $0) }
        if preprocessor { rules.append(Rule(.meta, P.cPreprocessor)) }
        if annotations { rules.append(Rule(.attribute, P.atAnnotation)) }
        rules += extra
        rules.append(Rule(.number, P.number))
        rules.append(Rule(.keyword, P.words(keywords)))
        if !literals.isEmpty { rules.append(Rule(.literal, P.words(literals))) }
        if !types.isEmpty { rules.append(Rule(.type, P.words(types))) }
        rules.append(Rule(.function, P.call))
        rules.append(Rule(.type, P.capitalized))
        return Language(id: id, name: name, rules: rules)
    }

    /// Scripting languages with `#` comments.
    static func hashStyle(
        _ id: String, _ name: String,
        keywords: String,
        literals: String = "true false",
        strings: [String] = [P.dq, P.sq],
        extra: [Rule] = [],
        caseInsensitive: Bool = false
    ) -> Language {
        var rules = [Rule(.comment, P.hashComment)]
        rules += strings.map { Rule(.string, $0) }
        rules += extra
        rules.append(Rule(.number, P.number))
        rules.append(Rule(.keyword, P.words(keywords, caseInsensitive: caseInsensitive)))
        if !literals.isEmpty { rules.append(Rule(.literal, P.words(literals, caseInsensitive: caseInsensitive))) }
        rules.append(Rule(.function, P.call))
        return Language(id: id, name: name, rules: rules)
    }
}

// MARK: - Definitions

extension Language {
    public static let plainText = Language(id: "text", name: "Plain Text", rules: [])

    static let swift = cStyle(
        "swift", "Swift",
        keywords: "associatedtype class deinit enum extension fileprivate func import init inout internal let open operator private precedencegroup protocol public rethrows static struct subscript typealias var break case catch continue default defer do else fallthrough for guard if in repeat return throw throws switch where while as is try await async actor nonisolated isolated some any consuming borrowing mutating nonmutating override final lazy weak unowned required convenience dynamic indirect get set willSet didSet macro package sending self Self super",
        types: "Int Int8 Int16 Int32 Int64 UInt UInt8 UInt16 UInt32 UInt64 Double Float CGFloat String Bool Character Array Dictionary Set Optional Void Never Any AnyObject",
        literals: "true false nil",
        strings: [P.tripleDQ, ##"#*"(?:[^"\\\n]|\\.)*"#*"##],
        extra: [
            Rule(.attribute, P.atAnnotation),
            Rule(.meta, #"#(?:if|elseif|else|endif|available|unavailable|selector|keyPath|file|line|function|warning|error|Preview|expect|externalMacro|sourceLocation)\b"#),
        ]
    )

    static let c = cStyle(
        "c", "C",
        keywords: "auto break case const continue default do else enum extern for goto if inline register restrict return sizeof static struct switch typedef union volatile while _Alignas _Alignof _Atomic _Bool _Complex _Generic _Noreturn _Static_assert _Thread_local",
        types: "void char short int long float double signed unsigned size_t ssize_t int8_t int16_t int32_t int64_t uint8_t uint16_t uint32_t uint64_t bool FILE",
        literals: "true false NULL",
        preprocessor: true
    )

    static let cpp = cStyle(
        "cpp", "C++",
        keywords: "alignas alignof and asm auto break case catch class const consteval constexpr constinit const_cast continue co_await co_return co_yield decltype default delete do dynamic_cast else enum explicit export extern for friend goto if inline mutable namespace new noexcept not operator or private protected public register reinterpret_cast requires return sizeof static static_assert static_cast struct switch template this thread_local throw try typedef typeid typename union using virtual volatile while override final concept module import",
        types: "void char char8_t char16_t char32_t wchar_t short int long float double signed unsigned bool size_t string vector map set unique_ptr shared_ptr",
        literals: "true false nullptr NULL",
        preprocessor: true
    )

    static let objc = cStyle(
        "objc", "Objective-C",
        keywords: "auto break case const continue default do else enum extern for goto if inline register return sizeof static struct switch typedef union volatile while self super id instancetype nonatomic atomic strong weak copy assign retain readonly readwrite nullable nonnull class",
        types: "void char short int long float double signed unsigned BOOL NSInteger NSUInteger CGFloat SEL IMP Class",
        literals: "YES NO nil Nil NULL true false",
        strings: [#"@?"(?:[^"\\\n]|\\.)*""#, P.sq],
        extra: [Rule(.keyword, #"@[a-z]+\b"#)],
        preprocessor: true
    )

    static let csharp = cStyle(
        "csharp", "C#",
        keywords: "abstract as base break case catch checked class const continue default delegate do else enum event explicit extern finally fixed for foreach goto if implicit in interface internal is lock namespace new operator out override params private protected public readonly record ref return sealed sizeof stackalloc static struct switch this throw try typeof unchecked unsafe using virtual volatile while async await var get set init value yield where when with required file global",
        types: "bool byte char decimal double float int long object sbyte short string uint ulong ushort void dynamic nint nuint",
        strings: [#"\$?@?"(?:[^"\\\n]|\\.|"")*""#, P.sq],
        extra: [Rule(.attribute, #"^\s*\[[A-Za-z][^\]\n]*\]"#)],
        preprocessor: true
    )

    static let java = cStyle(
        "java", "Java",
        keywords: "abstract assert break case catch class const continue default do else enum exports extends final finally for goto if implements import instanceof interface module native new non-sealed package permits private protected public record requires return sealed static strictfp super switch synchronized this throw throws transient try var void volatile while yield",
        types: "boolean byte char double float int long short String Object Integer Long Boolean List Map Set",
        strings: [P.tripleDQ, P.dq, P.sq],
        annotations: true
    )

    static let kotlin = cStyle(
        "kotlin", "Kotlin",
        keywords: "as break class continue do else for fun if in interface is object package return super this throw try typealias typeof val var when while by catch constructor delegate dynamic field file finally get import init param property receiver set setparam where actual abstract annotation companion const crossinline data enum expect external final infix inline inner internal lateinit noinline open operator out override private protected public reified sealed suspend tailrec vararg value",
        types: "Int Long Short Byte Double Float Boolean Char String Unit Any Nothing List Map Set Array",
        strings: [P.tripleDQ, P.dq, P.sq],
        annotations: true
    )

    static let scala = cStyle(
        "scala", "Scala",
        keywords: "abstract case catch class def do else extends final finally for forSome if implicit import lazy match new object override package private protected return sealed super this throw trait try type val var while with yield given using enum export then end derives extension inline opaque transparent",
        literals: "true false null",
        strings: [P.tripleDQ, P.dq, P.sq],
        annotations: true
    )

    static let groovy = cStyle(
        "groovy", "Groovy",
        keywords: "abstract as assert break case catch class const continue def default do else enum extends final finally for goto if implements import in instanceof interface new package private protected public return static super switch this throw throws trait try var void while",
        strings: [P.tripleDQ, P.tripleSQ, P.dq, P.sq],
        annotations: true
    )

    static let go = cStyle(
        "go", "Go",
        keywords: "break case chan const continue default defer else fallthrough for func go goto if import interface map package range return select struct switch type var",
        types: "bool byte complex64 complex128 error float32 float64 int int8 int16 int32 int64 rune string uint uint8 uint16 uint32 uint64 uintptr any comparable",
        literals: "true false nil iota",
        strings: [P.dq, P.backtick, P.sq]
    )

    static let rust = cStyle(
        "rust", "Rust",
        keywords: "as async await break const continue crate dyn else enum extern fn for if impl in let loop match mod move mut pub ref return self Self static struct super trait type union unsafe use where while macro_rules yield",
        types: "i8 i16 i32 i64 i128 isize u8 u16 u32 u64 u128 usize f32 f64 bool char str String Vec Option Result Box Rc Arc",
        literals: "true false None Some Ok Err",
        strings: [##"b?r#*"[\s\S]*?"#*"##, #"b?"(?:[^"\\]|\\.)*""#, #"b?'(?:[^'\\\n]|\\.[^'\n]*)'"#],
        extra: [
            Rule(.attribute, #"#!?\[[^\]\n]*\]"#),
            Rule(.variable, #"'[A-Za-z_]\w*\b"#),
            Rule(.meta, #"\b[a-z_]\w*!"#),
        ]
    )

    static let javascript = cStyle(
        "javascript", "JavaScript",
        keywords: "async await break case catch class const continue debugger default delete do else export extends finally for from function get if import in instanceof let new of return set static super switch this throw try typeof var void while with yield",
        literals: "true false null undefined NaN Infinity",
        strings: [P.dq, P.sq, P.backtick],
        extra: [
            Rule(.string, #"(?<=[=(,:;!&|?{}\[]|return|^)\s*/(?![*/])(?:[^/\\\n\[]|\\.|\[(?:[^\]\\\n]|\\.)*\])+/[dgimsuyv]*"#),
            Rule(.tag, P.jsxTag),
        ],
        annotations: true
    )

    static let typescript = cStyle(
        "typescript", "TypeScript",
        keywords: "abstract any as asserts async await boolean break case catch class const constructor continue debugger declare default delete do else enum export extends finally for from function get if implements import in infer instanceof interface is keyof let module namespace never new number object of override private protected public readonly require return satisfies set static string super switch symbol this throw try type typeof unique unknown var void while with yield",
        literals: "true false null undefined NaN Infinity",
        strings: [P.dq, P.sq, P.backtick],
        extra: [Rule(.tag, P.jsxTag)],
        annotations: true
    )

    static let dart = cStyle(
        "dart", "Dart",
        keywords: "abstract as assert async await base break case catch class const continue covariant default deferred do dynamic else enum export extends extension external factory final finally for Function get hide if implements import in interface is late library mixin new on operator part required rethrow return sealed set show static super switch sync this throw try typedef var void when while with yield",
        types: "int double num String bool List Map Set Future Stream Object",
        strings: [P.tripleDQ, P.tripleSQ, P.dq, P.sq],
        annotations: true
    )

    static let python = Language(id: "python", name: "Python", rules: [
        Rule(.comment, P.hashComment),
        Rule(.string, #"(?:\b[rRbBuUfF]{1,2})?(?:"""[\s\S]*?"""|'''[\s\S]*?''')"#),
        Rule(.string, #"(?:\b[rRbBuUfF]{1,2})?(?:"(?:[^"\\\n]|\\.)*"|'(?:[^'\\\n]|\\.)*')"#),
        Rule(.attribute, #"^\s*@[\w.]+"#),
        Rule(.number, P.number),
        Rule(.keyword, P.words("and as assert async await break class continue def del elif else except finally for from global if import in is lambda nonlocal not or pass raise return try while with yield match case type self cls")),
        Rule(.literal, P.words("True False None")),
        Rule(.type, P.words("int float str bool list dict set tuple bytes object complex frozenset")),
        Rule(.function, P.call),
        Rule(.type, P.capitalized),
    ])

    static let ruby = hashStyle(
        "ruby", "Ruby",
        keywords: "alias and begin break case class def defined? do else elsif end ensure for if in module next not or redo rescue retry return self super then undef unless until when while yield require require_relative include extend attr_accessor attr_reader attr_writer private protected public lambda proc raise",
        literals: "true false nil",
        extra: [
            Rule(.comment, #"^=begin[\s\S]*?^=end"#),
            Rule(.literal, #":[A-Za-z_]\w*[?!]?"#),
            Rule(.variable, #"@{1,2}[A-Za-z_]\w*|\$[A-Za-z_]\w*"#),
            Rule(.type, P.capitalized),
        ]
    )

    static let php = cStyle(
        "php", "PHP",
        keywords: "abstract and array as break callable case catch class clone const continue declare default do echo else elseif empty enddeclare endfor endforeach endif endswitch endwhile enum extends final finally fn for foreach function global goto if implements include include_once instanceof insteadof interface isset list match namespace new or print private protected public readonly require require_once return static switch throw trait try unset use var while xor yield",
        literals: "true false null TRUE FALSE NULL",
        prefix: [Rule(.comment, #"#(?!\[).*"#), Rule(.meta, #"<\?(?:php|=)?|\?>"#)],
        extra: [Rule(.variable, #"\$[A-Za-z_]\w*"#), Rule(.attribute, #"#\[[^\]\n]*\]"#)]
    )

    static let shell = Language(id: "shell", name: "Shell", rules: [
        Rule(.meta, #"^#!.*"#),
        Rule(.comment, #"(?<![\w$])#.*"#),
        Rule(.string, #""(?:[^"\\]|\\.)*""#),
        Rule(.string, #"'[^']*'"#),
        Rule(.variable, #"\$\{[^}\n]*\}|\$\(|\$[A-Za-z_]\w*|\$[0-9@#?$!*-]"#),
        Rule(.number, #"\b\d+\b"#),
        Rule(.keyword, P.words("if then else elif fi case esac for while until do done in function select time return break continue exit export local readonly declare typeset unset shift source alias eval exec trap set")),
        Rule(.function, #"^\s*[A-Za-z_][\w-]*(?=\s*\(\))"#),
        Rule(.literal, P.words("true false")),
        Rule(.attribute, #"(?<=\s)--?[A-Za-z][\w-]*"#),
    ])

    static let powershell = hashStyle(
        "powershell", "PowerShell",
        keywords: "begin break catch class continue data define do dynamicparam else elseif end enum exit filter finally for foreach from function hidden if in param process return static switch throw trap try until using var while",
        literals: "$true $false $null",
        extra: [
            Rule(.comment, #"<#[\s\S]*?#>"#),
            Rule(.variable, #"\$[A-Za-z_][\w:]*"#),
            Rule(.function, #"\b[A-Z][a-z]+-[A-Z]\w*"#),
        ],
        caseInsensitive: true
    )

    static let perl = hashStyle(
        "perl", "Perl",
        keywords: "my our local sub if elsif else unless while until for foreach last next redo return use no require package BEGIN END do eval die warn print printf and or not qw",
        literals: "",
        extra: [Rule(.variable, #"[$@%][A-Za-z_]\w*"#)]
    )

    static let lua = Language(id: "lua", name: "Lua", rules: [
        Rule(.comment, #"--\[=*\[[\s\S]*?\]=*\]"#),
        Rule(.comment, P.dashComment),
        Rule(.string, #"\[=*\[[\s\S]*?\]=*\]"#),
        Rule(.string, P.dq), Rule(.string, P.sq),
        Rule(.number, P.number),
        Rule(.keyword, P.words("and break do else elseif end for function goto if in local not or repeat return then until while")),
        Rule(.literal, P.words("true false nil")),
        Rule(.function, P.call),
    ])

    static let r = hashStyle(
        "r", "R",
        keywords: "if else repeat while function for in next break library require return",
        literals: "TRUE FALSE NULL NA Inf NaN T F",
        extra: [Rule(.keyword, #"<-|->"#)]
    )

    static let sql = Language(id: "sql", name: "SQL", rules: [
        Rule(.comment, P.dashComment),
        Rule(.comment, P.blockComment),
        Rule(.string, #"'(?:[^']|'')*'"#),
        Rule(.string, #""(?:[^"]|"")*"|`[^`]*`"#),
        Rule(.number, P.number),
        Rule(.keyword, P.words("add all alter and any as asc begin between by case check column commit constraint create cross database default delete desc distinct drop else end exists foreign from full group having if in index inner insert into is join key left like limit not null offset on or order outer primary procedure references replace returning right rollback select set table then top transaction trigger truncate union unique update values view when where with", caseInsensitive: true)),
        Rule(.type, P.words("int integer bigint smallint tinyint serial decimal numeric real float double varchar char text blob boolean bool date time timestamp timestamptz datetime json jsonb uuid bytea", caseInsensitive: true)),
        Rule(.literal, P.words("true false null", caseInsensitive: true)),
        Rule(.function, P.call),
    ])

    static let haskell = cStyle(
        "haskell", "Haskell",
        keywords: "case class data default deriving do else forall foreign hiding if import in infix infixl infixr instance let module newtype of qualified then type where",
        literals: "True False Nothing Just",
        strings: [P.dq],
        lineComment: P.dashComment,
        blockComment: #"\{-[\s\S]*?-\}"#
    )

    static let elixir = hashStyle(
        "elixir", "Elixir",
        keywords: "after alias and case catch cond def defp defmacro defmodule defprotocol defimpl defstruct do else end fn for if import in not or quote raise receive require rescue try unless unquote use when with",
        literals: "true false nil",
        strings: [P.tripleDQ, P.dq, P.sq],
        extra: [
            Rule(.literal, #"(?<!:):[A-Za-z_]\w*[?!]?"#),
            Rule(.attribute, #"@[a-z_]\w*"#),
            Rule(.type, P.capitalized),
        ]
    )

    static let erlang = Language(id: "erlang", name: "Erlang", rules: [
        Rule(.comment, #"%.*"#),
        Rule(.string, P.dq),
        Rule(.meta, #"^-[a-z_]+"#),
        Rule(.number, P.number),
        Rule(.keyword, P.words("after and andalso band begin bnot bor bsl bsr bxor case catch cond div end fun if let not of or orelse receive rem try when xor")),
        Rule(.variable, #"\b[A-Z_]\w*"#),
        Rule(.function, P.call),
    ])

    static let clojure = Language(id: "clojure", name: "Clojure", rules: [
        Rule(.comment, #";.*"#),
        Rule(.string, #""(?:[^"\\]|\\.)*""#),
        Rule(.literal, #":[\w\-./?!*+<>=]+"#),
        Rule(.number, P.number),
        Rule(.keyword, #"(?<=\()(?:def|defn|defn-|defmacro|defprotocol|defrecord|defmulti|defmethod|fn|let|if|when|cond|do|loop|recur|ns|require|import|try|catch|finally|throw)(?=[\s)])"#),
        Rule(.literal, P.words("true false nil")),
        Rule(.function, #"(?<=\()[\w\-./?!*+<>=]+"#),
    ])

    static let lisp = Language(id: "lisp", name: "Lisp", rules: [
        Rule(.comment, #";.*"#),
        Rule(.comment, #"#\|[\s\S]*?\|#"#),
        Rule(.string, #""(?:[^"\\]|\\.)*""#),
        Rule(.literal, #"(?<![\w-]):[\w\-]+|#[tf]\b|'[\w\-]+"#),
        Rule(.number, P.number),
        Rule(.keyword, #"(?<=\()(?:defun|defmacro|defvar|defparameter|defconst|define|lambda|let\*?|if|cond|when|unless|progn|setq|setf|loop|and|or|not|quote|require|provide)(?=[\s)])"#),
        Rule(.function, #"(?<=\()[\w\-*+/<>=!?]+"#),
    ])

    static let ocaml = cStyle(
        "ocaml", "OCaml / F#",
        keywords: "and as assert begin class constraint do done downto else end exception external for fun function functor if in include inherit initializer lazy let match method module mutable new nonrec object of open or private rec sig struct then to try type val virtual when while with member abstract default override namespace use yield async",
        literals: "true false None Some",
        strings: [P.dq],
        lineComment: #"//.*"#,
        blockComment: #"\(\*[\s\S]*?\*\)"#
    )

    static let zig = cStyle(
        "zig", "Zig",
        keywords: "addrspace align allowzero and anyframe anytype asm async await break callconv catch comptime const continue defer else enum errdefer error export extern fn for if inline linksection noalias noinline nosuspend opaque or orelse packed pub resume return struct suspend switch test threadlocal try union unreachable usingnamespace var volatile while",
        types: "i8 i16 i32 i64 i128 isize u8 u16 u32 u64 u128 usize f16 f32 f64 f128 bool void type anyerror noreturn",
        literals: "true false null undefined",
        extra: [Rule(.meta, #"@[A-Za-z_]\w*"#)],
        blockComment: nil
    )

    static let nim = hashStyle(
        "nim", "Nim",
        keywords: "addr and as asm bind block break case cast concept const continue converter defer discard distinct div do elif else end enum except export finally for from func if import in include interface is isnot iterator let macro method mixin mod nil not notin object of or out proc ptr raise ref return shl shr static template try tuple type using var when while xor yield",
        literals: "true false nil",
        strings: [P.tripleDQ, P.dq, P.sq]
    )

    static let julia = hashStyle(
        "julia", "Julia",
        keywords: "baremodule begin break catch const continue do else elseif end export finally for function global if import let local macro module quote return struct try using while abstract mutable primitive type where in isa",
        literals: "true false nothing missing",
        strings: [P.tripleDQ, P.dq, P.sq],
        extra: [Rule(.comment, #"#=[\s\S]*?=#"#), Rule(.meta, #"@\w+"#), Rule(.type, P.capitalized)]
    )

    static let solidity = cStyle(
        "solidity", "Solidity",
        keywords: "pragma solidity import contract interface library abstract is function modifier event struct enum mapping public private internal external pure view payable constant immutable returns return if else for while do break continue emit require revert assert new delete memory storage calldata using override virtual constructor fallback receive unchecked try catch",
        types: "address bool string bytes int uint int256 uint256 uint8 bytes32",
        literals: "true false"
    )

    static let verilog = cStyle(
        "verilog", "Verilog",
        keywords: "module endmodule input output inout wire reg logic always always_ff always_comb assign begin end if else case endcase for parameter localparam posedge negedge initial function endfunction task endtask generate endgenerate integer",
        literals: "",
        strings: [P.dq],
        extra: [Rule(.meta, #"`\w+"#), Rule(.number, #"\d*'[bBoOdDhH][0-9a-fA-FxXzZ_]+"#)]
    )

    static let vhdl = Language(id: "vhdl", name: "VHDL", rules: [
        Rule(.comment, P.dashComment),
        Rule(.string, P.dq),
        Rule(.number, P.number),
        Rule(.keyword, P.words("library use entity is port in out inout end architecture of signal begin process if then else elsif case when others generic map component constant variable type subtype array range to downto loop for while wait until return function procedure package body", caseInsensitive: true)),
        Rule(.type, P.words("std_logic std_logic_vector integer boolean natural positive unsigned signed bit", caseInsensitive: true)),
    ])

    static let fortran = Language(id: "fortran", name: "Fortran", rules: [
        Rule(.comment, #"!.*"#),
        Rule(.string, P.dq), Rule(.string, P.sq),
        Rule(.number, P.number),
        Rule(.keyword, P.words("program end subroutine function module use implicit none integer real double precision complex logical character dimension allocatable intent in out inout if then else elseif do while call return contains type select case stop print write read", caseInsensitive: true)),
    ])

    static let pascal = cStyle(
        "pascal", "Pascal",
        keywords: "and array as begin case class const constructor destructor div do downto else end except file finally for function goto if implementation in inherited interface is label mod nil not object of or out packed procedure program property raise record repeat set shl shr string then to try type unit until uses var while with xor",
        literals: "true false nil",
        strings: [#"'(?:[^']|'')*'"#],
        blockComment: #"\{[\s\S]*?\}|\(\*[\s\S]*?\*\)"#
    )

    static let ada = Language(id: "ada", name: "Ada", rules: [
        Rule(.comment, P.dashComment),
        Rule(.string, P.dq),
        Rule(.number, P.number),
        Rule(.keyword, P.words("abort abs accept access all and array at begin body case constant declare delay delta digits do else elsif end entry exception exit for function generic goto if in is limited loop mod new not null of or others out package pragma private procedure raise range record rem renames return reverse select separate subtype task terminate then type until use when while with xor", caseInsensitive: true)),
    ])

    static let vb = Language(id: "vb", name: "Visual Basic", rules: [
        Rule(.comment, #"'.*|(?i:\bREM\b).*"#),
        Rule(.string, #""(?:[^"]|"")*""#),
        Rule(.number, P.number),
        Rule(.keyword, P.words("as boolean byref byval call case class const dim do each else elseif end exit false for function get if in integer is loop me module new next not nothing of on option or private property public return select set string sub then to true while with", caseInsensitive: true)),
    ])

    static let batch = Language(id: "batch", name: "Batch", rules: [
        Rule(.comment, #"(?i:^\s*(?:rem\b|::)).*"#),
        Rule(.string, P.dq),
        Rule(.variable, #"%[\w~]+%?|!\w+!"#),
        Rule(.function, #"^\s*:\w+"#),
        Rule(.keyword, P.words("echo set if else for in do goto call exit not exist defined errorlevel setlocal endlocal pushd popd shift start", caseInsensitive: true)),
    ])

    static let awk = hashStyle(
        "awk", "AWK",
        keywords: "BEGIN END function if else while for do break continue next exit return delete in getline print printf",
        literals: "",
        extra: [Rule(.variable, #"\$\w+"#)]
    )

    static let tcl = hashStyle(
        "tcl", "Tcl",
        keywords: "proc set if else elseif for foreach while return puts expr global upvar namespace package source switch catch",
        literals: "",
        extra: [Rule(.variable, #"\$[\w:]+"#)]
    )

    static let crystal = hashStyle(
        "crystal", "Crystal",
        keywords: "abstract alias annotation as begin break case class def do else elsif end ensure enum extend for fun if in include lib macro module next of out private protected require rescue return select self struct super then type typeof union unless until when while with yield",
        literals: "true false nil",
        extra: [Rule(.literal, #":[A-Za-z_]\w*"#), Rule(.variable, #"@{1,2}\w+"#), Rule(.type, P.capitalized)]
    )

    static let d = cStyle(
        "d", "D",
        keywords: "abstract alias align asm assert auto body break case cast catch class const continue debug default delegate delete deprecated do else enum export extern final finally for foreach foreach_reverse function goto if immutable import in inout interface invariant is lazy mixin module new nothrow out override package pragma private protected public pure ref return scope shared static struct super switch synchronized template this throw try typeid typeof union unittest version while with",
        types: "void bool byte ubyte short ushort int uint long ulong float double real char wchar dchar string size_t",
        literals: "true false null"
    )

    static let v = cStyle(
        "v", "V",
        keywords: "as asm assert atomic break const continue defer else enum fn for go goto if import in interface is isreftype lock match module mut or pub return rlock select shared sizeof static struct type typeof union unsafe",
        literals: "true false none"
    )

    static let odin = cStyle(
        "odin", "Odin",
        keywords: "package import proc struct enum union map dynamic if else for in not_in switch case defer return break continue fallthrough when where using distinct cast transmute auto_cast or_else or_return context",
        literals: "true false nil",
        extra: [Rule(.meta, #"#\w+"#), Rule(.attribute, #"@\([^)\n]*\)|@\w+"#)]
    )

    static let gleam = cStyle(
        "gleam", "Gleam",
        keywords: "as assert case const external fn if import let opaque panic pub todo type use",
        literals: "True False Nil",
        strings: [P.dq]
    )

    static let metal = cStyle(
        "metal", "Metal",
        keywords: "using namespace struct constant device thread threadgroup kernel vertex fragment return if else for while constexpr template typename static inline const",
        types: "float float2 float3 float4 float4x4 half half2 half3 half4 int uint uint2 bool texture2d sampler",
        extra: [Rule(.attribute, #"\[\[[^\]\n]*\]\]"#)],
        preprocessor: true
    )

    static let glsl = cStyle(
        "glsl", "Shader",
        keywords: "attribute const uniform varying layout centroid flat smooth break continue do for while switch case default if else in out inout return discard struct precision highp mediump lowp fn let var",
        types: "void bool int uint float double vec2 vec3 vec4 ivec2 ivec3 ivec4 mat2 mat3 mat4 sampler2D samplerCube float2 float3 float4 f32 i32 u32",
        extra: [Rule(.attribute, #"@\w+"#)],
        preprocessor: true
    )

    static let html = Language(id: "html", name: "HTML", rules: [
        Rule(.comment, #"<!--[\s\S]*?-->"#),
        Rule(.meta, #"<![A-Za-z][^>]*>"#),
        Rule(.tag, #"</?[A-Za-z][\w:.-]*|/?>"#),
        Rule(.attributeName, #"(?<=\s)[@:#]?[A-Za-z_][\w:.-]*(?=\s*=)"#),
        Rule(.string, #""[^"]*"(?=[\s/>])|'[^']*'(?=[\s/>])"#),
        Rule(.variable, #"\{\{[\s\S]*?\}\}|\{%[\s\S]*?%\}"#),
        Rule(.literal, #"&#?\w+;"#),
    ])

    static let xml = Language(id: "xml", name: "XML", rules: [
        Rule(.comment, #"<!--[\s\S]*?-->"#),
        Rule(.string, #"<!\[CDATA\[[\s\S]*?\]\]>"#),
        Rule(.meta, #"<\?[\s\S]*?\?>|<![A-Za-z][^>]*>"#),
        Rule(.tag, #"</?[A-Za-z_][\w:.-]*|/?>"#),
        Rule(.attributeName, #"(?<=\s)[A-Za-z_][\w:.-]*(?=\s*=)"#),
        Rule(.string, #""[^"]*"(?=[\s/>?])|'[^']*'(?=[\s/>?])"#),
        Rule(.literal, #"&#?\w+;"#),
    ])

    static let css = Language(id: "css", name: "CSS", rules: [
        Rule(.comment, P.blockComment),
        Rule(.comment, #"(?<!:)//.*"#),
        Rule(.string, P.dq), Rule(.string, P.sq),
        Rule(.keyword, #"@[\w-]+"#),
        Rule(.number, #"#[0-9a-fA-F]{3,8}\b"#),
        Rule(.variable, #"--[\w-]+|\$[\w-]+"#),
        Rule(.attributeName, #"(?<![\w-])[a-z-]+(?=\s*:(?!:)[^{;\n]*[;}\n])"#),
        Rule(.number, #"(?<![\w-])-?\d*\.?\d+(?:px|em|rem|%|vh|vw|vmin|vmax|s|ms|deg|fr|ch|pt|dvh|svh|lvh)?\b"#),
        Rule(.literal, #"!important\b"#),
        Rule(.function, P.call),
        Rule(.tag, #"[.#][A-Za-z_][\w-]*|&"#),
        Rule(.attribute, #"::?[\w-]+"#),
    ])

    static let json = Language(id: "json", name: "JSON", rules: [
        Rule(.comment, P.slashComment),
        Rule(.comment, P.blockComment),
        Rule(.attributeName, #""(?:[^"\\\n]|\\.)*"(?=\s*:)"#),
        Rule(.string, P.dq),
        Rule(.number, #"-?\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b"#),
        Rule(.literal, P.words("true false null")),
    ])

    static let yaml = Language(id: "yaml", name: "YAML", rules: [
        Rule(.comment, #"(?<!\S)#.*"#),
        Rule(.meta, #"^(?:---|\.\.\.)\s*$|^%.*"#),
        Rule(.attributeName, #"^[ \t]*(?:-[ \t]+)?[^\s#:'"\-][^#:\n]*?(?=:(?:\s|$))|^[ \t]*(?:-[ \t]+)?(?:"[^"\n]*"|'[^'\n]*')(?=:(?:\s|$))"#),
        Rule(.string, P.dq), Rule(.string, #"'(?:[^']|'')*'"#),
        Rule(.variable, #"[&*][\w-]+|!!?\w+"#),
        Rule(.number, #"(?<=[:\-\[,]\s)-?\d+(?:\.\d+)?\s*$"#),
        Rule(.literal, #"(?<=:\s)(?:true|false|null|yes|no|on|off|~)\s*$"#),
        Rule(.keyword, #"^[ \t]*-(?=\s)|[|>][-+]?\s*$"#),
    ])

    static let toml = Language(id: "toml", name: "TOML", rules: [
        Rule(.comment, P.hashComment),
        Rule(.type, #"^\s*\[\[?[^\]\n]*\]\]?"#),
        Rule(.attributeName, #"^\s*[\w.\-"']+(?=\s*=)"#),
        Rule(.string, P.tripleDQ), Rule(.string, P.tripleSQ),
        Rule(.string, P.dq), Rule(.string, #"'[^'\n]*'"#),
        Rule(.number, #"\b\d{4}-\d{2}-\d{2}(?:[T ]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})?)?|[+-]?\b\d[\d_]*(?:\.\d+)?(?:[eE][+-]?\d+)?\b"#),
        Rule(.literal, P.words("true false")),
    ])

    static let ini = Language(id: "ini", name: "Config", rules: [
        Rule(.comment, #"^\s*[#;].*"#),
        Rule(.type, #"^\s*\[[^\]\n]*\]"#),
        Rule(.attributeName, #"^\s*(?:export\s+)?[\w.\-/ ]+?(?=\s*[=:])"#),
        Rule(.string, P.dq), Rule(.string, P.sq),
        Rule(.variable, #"\$\{[^}\n]*\}|\$\w+|%\([\w]+\)s"#),
        Rule(.number, #"(?<==)\s*-?\d+(?:\.\d+)?\s*$"#),
        Rule(.literal, #"(?i:(?<==)\s*(?:true|false|yes|no|on|off)\s*$)"#),
    ])

    static let dockerfile = Language(id: "dockerfile", name: "Dockerfile", rules: [
        Rule(.comment, #"^\s*#.*"#),
        Rule(.keyword, #"(?i:^\s*(?:FROM|RUN|CMD|LABEL|MAINTAINER|EXPOSE|ENV|ADD|COPY|ENTRYPOINT|VOLUME|USER|WORKDIR|ARG|ONBUILD|STOPSIGNAL|HEALTHCHECK|SHELL)\b)"#),
        Rule(.keyword, #"(?i:\bAS\b)"#),
        Rule(.string, P.dq), Rule(.string, P.sq),
        Rule(.variable, #"\$\{[^}\n]*\}|\$\w+"#),
        Rule(.attribute, #"(?<=\s)--[\w-]+"#),
        Rule(.number, #"\b\d+\b"#),
    ])

    static let makefile = Language(id: "makefile", name: "Makefile", rules: [
        Rule(.comment, P.hashComment),
        Rule(.string, P.dq), Rule(.string, P.sq),
        Rule(.variable, #"\$[({][^)}\n]*[)}]|\$[@<^?*%+]|\$\w"#),
        Rule(.keyword, #"^\s*(?:include|-include|sinclude|ifeq|ifneq|ifdef|ifndef|else|endif|define|endef|export|unexport|override|vpath)\b"#),
        Rule(.function, #"^[^\s:#=][^:#=\n]*(?=:(?!=))"#),
        Rule(.attributeName, #"^\s*[\w.\-]+(?=\s*(?:[:+?!]?=))"#),
    ])

    static let cmake = Language(id: "cmake", name: "CMake", rules: [
        Rule(.comment, P.hashComment),
        Rule(.string, #""(?:[^"\\]|\\.)*""#),
        Rule(.variable, #"\$\{[^}\n]*\}|\$ENV\{[^}\n]*\}"#),
        Rule(.function, P.call),
        Rule(.literal, #"\b[A-Z][A-Z0-9_]{2,}\b"#),
    ])

    static let diff = Language(id: "diff", name: "Diff", rules: [
        Rule(.meta, #"^(?:diff|index|---|\+\+\+|new file|deleted file|similarity|rename).*"#),
        Rule(.keyword, #"^@@.*"#),
        Rule(.inserted, #"^\+.*"#),
        Rule(.deleted, #"^-.*"#),
        Rule(.comment, #"^\\.*"#),
    ])

    static let graphql = Language(id: "graphql", name: "GraphQL", rules: [
        Rule(.comment, P.hashComment),
        Rule(.string, P.tripleDQ), Rule(.string, P.dq),
        Rule(.variable, #"\$\w+"#),
        Rule(.attribute, #"@\w+"#),
        Rule(.number, P.number),
        Rule(.keyword, P.words("query mutation subscription fragment on type interface union enum input scalar schema extend directive implements repeatable")),
        Rule(.literal, P.words("true false null")),
        Rule(.type, P.capitalized),
        Rule(.attributeName, #"\b\w+(?=\s*[:(])"#),
    ])

    static let proto = cStyle(
        "proto", "Protocol Buffers",
        keywords: "syntax edition package import option message enum service rpc returns stream oneof map repeated optional required reserved extend extensions public weak to max",
        types: "double float int32 int64 uint32 uint64 sint32 sint64 fixed32 fixed64 sfixed32 sfixed64 bool string bytes",
        literals: "true false"
    )

    static let hcl = Language(id: "hcl", name: "HCL", rules: [
        Rule(.comment, #"#.*|//.*"#), Rule(.comment, P.blockComment),
        Rule(.string, #"<<-?\s*\w+[\s\S]*?^\s*\w+$"#),
        Rule(.string, #""(?:[^"\\]|\\.)*""#),
        Rule(.keyword, #"^\s*(?:resource|data|variable|output|locals|module|provider|terraform|backend|required_providers|dynamic|moved|import|check)\b"#),
        Rule(.attributeName, #"^\s*[\w-]+(?=\s*=)"#),
        Rule(.number, P.number),
        Rule(.literal, P.words("true false null")),
        Rule(.keyword, P.words("for in if var local each count self path")),
        Rule(.function, P.call),
    ])

    static let nix = Language(id: "nix", name: "Nix", rules: [
        Rule(.comment, P.hashComment), Rule(.comment, P.blockComment),
        Rule(.string, #"''[\s\S]*?''"#), Rule(.string, #""(?:[^"\\]|\\.)*""#),
        Rule(.string, #"(?:\.{0,2}/|~/)[\w./-]+|<[\w./-]+>"#),
        Rule(.keyword, P.words("let in with rec inherit if then else assert import")),
        Rule(.literal, P.words("true false null")),
        Rule(.attributeName, #"[\w\-.]+(?=\s*=)"#),
        Rule(.number, P.number),
    ])

    static let vim = Language(id: "vim", name: "Vim Script", rules: [
        Rule(.comment, #"^\s*".*"#),
        Rule(.string, P.sq), Rule(.string, P.dq),
        Rule(.keyword, P.words("if else elseif endif for endfor while endwhile function endfunction return let set map nnoremap inoremap vnoremap noremap autocmd augroup call execute syntax highlight command")),
        Rule(.variable, #"\b[gslabwtv]:\w+|&\w+"#),
        Rule(.number, P.number),
    ])

    static let assembly = Language(id: "asm", name: "Assembly", rules: [
        Rule(.comment, #"[;#@].*|//.*"#),
        Rule(.string, P.dq), Rule(.string, P.sq),
        Rule(.function, #"^\s*[\w.$]+:"#),
        Rule(.meta, #"^\s*\.[a-z]\w*"#),
        Rule(.variable, #"%\w+|\b(?:[re]?[abcd]x|[re]?[sd]i|[re]?[sb]p|r\d+[dwb]?|[xwqvsdh]\d+|sp|lr|pc|fp)\b"#),
        Rule(.number, #"\$?-?(?:0x[0-9a-fA-F]+|\d+)\b|#-?\d+"#),
    ])

    static let latex = Language(id: "latex", name: "LaTeX", rules: [
        Rule(.comment, #"(?<!\\)%.*"#),
        Rule(.string, #"\$\$[\s\S]*?\$\$|\$(?:[^$\\\n]|\\.)+\$"#),
        Rule(.keyword, #"\\(?:begin|end|section|subsection|subsubsection|chapter|part|documentclass|usepackage|include|input)\b"#),
        Rule(.function, #"\\[A-Za-z@]+\*?"#),
        Rule(.attribute, #"\[[^\]\n]*\]"#),
    ])

    static let markdown = Language(id: "markdown", name: "Markdown", rules: [
        Rule(.string, #"^[ \t]*(?:```|~~~)[\s\S]*?^[ \t]*(?:```|~~~)[ \t]*$"#),
        Rule(.comment, #"<!--[\s\S]*?-->"#),
        Rule(.heading, #"^#{1,6}[ \t].*"#),
        Rule(.heading, #"^.+\n(?:=+|-+)[ \t]*$"#),
        Rule(.meta, #"^[ \t]*(?:[-*+]|\d+[.)])(?=[ \t])|^[ \t]*(?:[-*_][ \t]*){3,}$"#),
        Rule(.comment, #"^>.*"#),
        Rule(.string, #"`[^`\n]+`"#),
        Rule(.link, #"!?\[[^\]\n]*\]\([^)\n]*\)|!?\[[^\]\n]*\]\[[^\]\n]*\]|^\[[^\]\n]+\]:.*|<https?://[^>\s]+>"#),
        Rule(.emphasis, #"\*\*[^*\n]+\*\*|__[^_\n]+__|(?<![*\w])\*[^*\s][^*\n]*\*|(?<![_\w])_[^_\s][^_\n]*_|~~[^~\n]+~~"#),
        Rule(.tag, #"</?[A-Za-z][\w-]*[^>\n]*>"#),
    ])

    static let ignoreFile = Language(id: "ignore", name: "Ignore List", rules: [
        Rule(.comment, #"^\s*#.*"#),
        Rule(.keyword, #"^\s*!"#),
        Rule(.meta, #"\*\*?|\?"#),
        Rule(.attribute, #"\[[^\]\n]*\]"#),
    ])

    /// Every defined language, used by tests to validate patterns.
    static let all: [Language] = [
        plainText, swift, c, cpp, objc, csharp, java, kotlin, scala, groovy, go, rust, javascript,
        typescript, dart, python, ruby, php, shell, powershell, perl, lua, r, sql, haskell, elixir,
        erlang, clojure, lisp, ocaml, zig, nim, julia, solidity, verilog, vhdl, fortran, pascal, ada,
        vb, batch, awk, tcl, crystal, d, v, odin, gleam, metal, glsl, html, xml, css, json, yaml,
        toml, ini, dockerfile, makefile, cmake, diff, graphql, proto, hcl, nix, vim, assembly, latex,
        markdown, ignoreFile,
    ]
}
