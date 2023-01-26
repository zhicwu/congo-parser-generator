[#ftl strict_vars=true]
// Generated by ${generated_by}. Do not edit.
// ReSharper disable InconsistentNaming
[#var csPackage = grammar.utils.getPreprocessorSymbol('cs.package', grammar.parserPackage) ]
namespace ${csPackage} {
    using System;
    using System.Collections.Generic;
    using System.Diagnostics;
    using System.Text;

    public class BitSet {
        private const uint BitsInWord = 64;

        private readonly int _nints;
        private readonly int _nbits;
        private readonly ulong[] _words;

        public int Length => _nbits;

        public BitSet(int bits) {
            _nbits = bits;
            _nints = (int) Math.Ceiling((double) bits / BitsInWord);
            _words = new ulong[_nints];
        }

        public bool IsEmpty {
            get {
                for (var i = 0; i < _nints; i++) {
                    if (_words[i] != 0) {
                        return false;
                    }
                }
                return true;
            }
        }

        public void Clear(int from = -1, int to = -1) {
            if (from < 0) {
                for (var i = 0; i < _nints; i++) {
                    _words[i] = 0;
                }
            }
            else {
                Debug.Assert(from < _nbits);
                Debug.Assert(to <= _nbits);
                Debug.Assert(from < to);
                var idx1 = from / BitsInWord;
                var bit1 = from % BitsInWord;
                var idx2 = --to / BitsInWord;
                var bit2 = to % BitsInWord;

                if ((idx1 == idx2) && (bit1 == bit2)) {
                    // just 1 bit to do
                    var mask1 = 1UL << (int) bit1;
                    _words[idx1] &= ~mask1;
                }
                else if (idx1 == idx2) {
                    // just one int to do
                    var mask1 = (1UL << (int) bit1) - 1;
                    var mask2 = (~((1UL << (int) bit2) - 1)) << 1;
                    _words[idx1] &= (mask1 | mask2);
                }
                else {
                    var mask1 = (1UL << (int) bit1) - 1;
                    var mask2 = (~((1UL << (int) bit2) - 1)) << 1;
                    _words[idx1] &= mask1;
                    _words[idx2] &= mask2;
                    // any in between first and last get zeroed
                    while (++idx1 < idx2) {
                        _words[idx1] = 0;
                    }
                }
            }
        }

        public void Set(int pos, bool value = true) {
            Debug.Assert(pos >= 0 && pos < _nbits);
            var idx = pos / BitsInWord;
            var bit = pos % BitsInWord;
            var mask = 1UL << (int) bit;
            if (value) {
                _words[idx] |= mask;
            }
            else {
                _words[idx] &= ~mask;
            }
        }

        public int NextSetBit(int pos) {
            Debug.Assert(pos >= 0);
            if (pos >= _nbits) {
                return -1;
            }
            var idx = pos / BitsInWord;
            var bit = pos % BitsInWord;
            var mask = 1UL << (int) bit;
            if ((_words[idx] & mask) != 0) {
                return pos;
            }
            for (;;) {
                var v = (long) (_words[idx] & ~(mask - 1));
                if (v == 0) {
                    idx++;
                    if (idx >= _nints) {
                        return -1;
                    }
                    mask = 1;
                    continue;
                }
                v &= -v;
                var uv = (ulong) v;
                int result = 0;
                while (uv != 1) {
                    result++;
                    uv >>= 1;
                }
                return result + (int) (BitsInWord * idx);
            }
        }

        public int PreviousSetBit(int pos) {
            Debug.Assert(pos < _nbits);
            if (pos < 0) {
                return -1;
            }

            var idx = pos / BitsInWord;
            var bit = pos % BitsInWord;
            var mask = 1UL << (int) bit;
            if ((_words[idx] & mask) != 0) {
                return pos;
            }
            mask = (bit == (BitsInWord - 1)) ? 0 : ~((mask << 1) - 1);
            for (;;) {
                var v = _words[idx] & ~mask;  // mask off higher bits
                if (v == 0) {
                    idx--;
                    if (idx < 0) {
                        return -1;
                    }
                    mask = 0;
                    continue;
                }
                int result = 0;
                while ((v >>= 1) != 0) {
                    result++;
                }
                return result + (int) (BitsInWord * idx);
            }
        }

        public bool this[int pos] {
            get {
                Debug.Assert(pos >= 0 && pos < _nbits, $"out of range: {pos} (should be in 0 .. {_nbits})");
                var idx = pos / BitsInWord;
                var bit = pos % BitsInWord;
                var mask = 1UL << (int) bit;
                return (_words[idx] & mask) != 0;
            }
        }
    }

[#var TABS_TO_SPACES = 0, PRESERVE_LINE_ENDINGS="true", JAVA_UNICODE_ESCAPE="false", ENSURE_FINAL_EOL = grammar.ensureFinalEOL?string("true", "false")]
[#if grammar.settings.TABS_TO_SPACES??]
   [#set TABS_TO_SPACES = grammar.settings.TABS_TO_SPACES]
[/#if]
[#if grammar.settings.PRESERVE_LINE_ENDINGS?? && !grammar.settings.PRESERVE_LINE_ENDINGS]
   [#set PRESERVE_LINE_ENDINGS = "false"]
[/#if]
[#if grammar.settings.JAVA_UNICODE_ESCAPE?? && grammar.settings.JAVA_UNICODE_ESCAPE]
   [#set JAVA_UNICODE_ESCAPE = "true"]
[/#if]

/*
    public class FileLineMap {
        public string InputSource { get; internal set; }
        public uint StartingLine { get; private set; }
        public uint StartingColumn { get; private set; }
        // Just used to "bookmark" the starting location for a token
        // for when we put in the location info at the end.
        public uint TokenBeginLine { get; set; }
        public uint TokenBeginColumn { get; set; }
        private uint _line;
        public uint Column { get; private set; }
        public BitSet ParsedLines { get; set; } // if set, determines which lines are parsed
        private readonly string _content;
        private readonly uint[] _lineOffsets;   // offsets to the beginnings of lines
        private uint _bufferPosition;

        private static readonly Regex PythonCodingPattern = new Regex(@"^[ \t\f]*#.*\bcoding[:=][ \t]*([-_.a-zA-Z0-9]+)");
        private static readonly UTF8Encoding Utf8 = new UTF8Encoding(true);
        private static readonly UnicodeEncoding Utf16Le = new UnicodeEncoding(false, true, true);
        private static readonly UnicodeEncoding Utf16Be = new UnicodeEncoding(true, true, true);
        private static readonly UTF32Encoding Utf32Le = new UTF32Encoding(false, true, true);
        private static readonly UTF32Encoding Utf32Be = new UTF32Encoding(true, true, true);

        public FileLineMap(string inputSource, uint line, uint column) {
            InputSource = inputSource;
            var fs = new FileStream(inputSource, FileMode.Open);
            var fileLen = (int) fs.Length;
            var bytes = new byte[fileLen];
            var bomLen = 3;
            Encoding encoding = null;
            var allBytes = new Span<byte>(bytes);
            Span<byte> bomBytes;
            Span<byte> foundBom = null;

            fs.Read(bytes, 0, fileLen);

            if (fileLen <= bomLen) {
                encoding = Utf8;
            }
            else if ((bomBytes = allBytes[..bomLen]) == Utf8.GetPreamble()) {
                encoding = Utf8;
                foundBom = bomBytes;
            }
            else if ((bomBytes = allBytes[..(bomLen = 2)]) == Utf16Le.GetPreamble()) {
                encoding = Utf16Le;
                foundBom = bomBytes;
            }
            else if (bomBytes == Utf16Be.GetPreamble()) {
                encoding = Utf16Be;
                foundBom = bomBytes;
            }
            else if ((bomBytes = allBytes[(bomLen = 4)..]) == Utf32Le.GetPreamble()) {
                encoding = Utf32Le;
                foundBom = bomBytes;
            }
            else if (bomBytes == Utf32Be.GetPreamble()) {
                encoding = Utf32Be;
                foundBom = bomBytes;
            }
            else {
                encoding = Utf8;
                if (inputSource.EndsWith(".py")) {
                    // Look for coding declared in first two lines
                    var pos = System.Array.IndexOf(bytes, '\n');
                    if (pos > 0) {
                        var s = Utf8.GetString(allBytes.Slice(0, pos));
                        var m = PythonCodingPattern.Match(s);

                        if (m.Success) {
                            s = m.Groups[1].Value;
                            encoding = Encoding.GetEncoding(s);
                        }
                        else {
                            pos = System.Array.IndexOf(bytes, '\n', pos + 1);
                            if (pos > 0) {
                                s = Utf8.GetString(allBytes.Slice(0, pos));
                                m = PythonCodingPattern.Match(s);
                                if (m.Success) {
                                    s = m.Groups[1].Value;
                                    encoding = Encoding.GetEncoding(s);
                                }
                            }
                        }
                    }
                }
            }
            var rest = (foundBom == null) ? allBytes : allBytes[bomLen..];
            _content = MungeContent(encoding.GetString(rest), ${TABS_TO_SPACES}, ${PRESERVE_LINE_ENDINGS}, ${JAVA_UNICODE_ESCAPE}, ${ENSURE_FINAL_EOL});
            _lineOffsets = CreateLineOffsetsTable(_content);
            SetStartPosition(line, column);
        }

        private void SetStartPosition(uint line, uint column) {
            Line = StartingLine = line;
            Column = StartingColumn = column;
        }

        private string MungeContent(string content, int tabsToSpaces, bool preserveLines,
                      bool unicodeEscape, bool ensureFinalEol)
        {
            StringBuilder buf;

            if (tabsToSpaces <= 0 && preserveLines && !unicodeEscape) {
                if (!ensureFinalEol) return content;
                if (content.Length == 0) {
                    content = "\n";
                }
                else {
                    int lastChar = content[^1];
                    if (lastChar == '\n' || lastChar == '\r') return content;
                    buf = new StringBuilder(content);
                    buf.Append('\n');
                    content = buf.ToString();
                }
                return content;
            }
            buf = new StringBuilder();
            // This is just to handle tabs to spaces. If you don't have that setting set, it
            // is really unused.
            var col = 0;
            var justSawUnicodeEscape = false;
            // There might be some better way of doing this ...
            var bytes = Encoding.UTF32.GetBytes(content);
            var codePoints = new int[bytes.Length / 4];
            Buffer.BlockCopy(bytes, 0, codePoints, 0, bytes.Length);
            for (var index = 0; index < codePoints.Length; )
            {
                var ch = codePoints[index++];
                switch (ch)
                {
                    case '\\' when unicodeEscape && index < codePoints.Length:
                    {
                        ch = codePoints[index++];
                        if (ch != 'u') {
                            justSawUnicodeEscape = false;
                            buf.Append('\\');
                            buf.Append((char) ch);
                            if (ch == '\n')
                                col = 0;
                            else
                                col += 2;
                        } else {
                            while (codePoints[index] == 'u') {
                                index++;
                                // col++;
                            }
                            var hexBuf = new StringBuilder(4);
                            for (var i = 0; i < 4; i++) hexBuf.Append((char) codePoints[index++]);
                            var current = (char) Convert.ToInt32(hexBuf.ToString(), 16);
                            var last = buf.Length > 0 ? buf[^1] : (char) 0;
                            if (justSawUnicodeEscape && char.IsSurrogatePair(last, current)) {
                                buf.Length -= 1;
                                --col;
                                buf.Append(char.ConvertToUtf32(last, current));
                                justSawUnicodeEscape = false;
                            } else {
                                buf.Append(current);
                                justSawUnicodeEscape = true;
                            }
                            // col +=6;
                            ++col;
                            // We're not going to be trying to track line/column information relative to the original content
                            // with tabs or unicode escape, so we just increment 1, not 6
                        }

                        break;
                    }
                    case '\r' when !preserveLines:
                    {
                        justSawUnicodeEscape = false;
                        buf.Append('\n');
                        if (index < codePoints.Length) {
                            ch = codePoints[index++];
                            if (ch != '\n') {
                                buf.Append((char) ch);
                                ++col;
                            }
                            else
                            {
                                col = 0;
                            }
                        }
                        break;
                    }
                    case '\t' when tabsToSpaces > 0:
                    {
                        justSawUnicodeEscape = false;
                        int spacesToAdd = tabsToSpaces - col % tabsToSpaces;
                        for (int i = 0; i < spacesToAdd; i++) {
                            buf.Append(' ');
                            col++;
                        }

                        break;
                    }
                    default:
                    {
                        justSawUnicodeEscape = false;
                        buf.Append((char) ch);
                        if (ch == '\n') {
                            col = 0;
                        } else
                            col++;

                        break;
                    }
                }
            }

            if (!ensureFinalEol) return buf.ToString();
            if (buf.Length == 0) {
                return "\n";
            }
            var lc = buf[^1];
            if (lc != '\n' && lc!='\r') buf.Append('\n');
            return buf.ToString();
        }

        private static readonly uint[] EmptyInt = new uint[] { 0 };

        private uint[] CreateLineOffsetsTable(string content) {
            if (content.Length == 0) {
                return EmptyInt;
            }
            var lineCount = 0;
            var length = content.Length;
            for (var i = 0; i < length; i++) {
                var ch = content[i];
                if (ch == '\n') {
                    lineCount++;
                }
            }
            if (content[^1] != '\n') {
                lineCount++;
            }
            var lineOffsets = new uint[lineCount];
            lineOffsets[0] = 0;
            var index = 1;
            for (var i = 0; i < length; i++) {
                var ch = content[i];
                if (ch != '\n') continue;
                if (i + 1 == length)
                    break;
                lineOffsets[index++] = (uint) (i + 1);
            }
            return lineOffsets;
        }

        private bool IsParsedLine(uint lineno) {
            var pos = (int) (1 + lineno - StartingLine);
            Debug.Assert(pos >= 0, $"out of range: computed {pos}, should be non-negative");
            return (ParsedLines == null) || ParsedLines[pos];
        }

        public uint Line {
            get {
                if (!IsParsedLine(_line)) {
                    AdvanceLine();
                }
                return _line;
            }
            set {
                _line = value;
            }
        }

        internal uint EndLine {
            get {
                return ((Column == 1) && (Line > TokenBeginLine)) ? Line - 1 : Line;
            }
        }

        internal uint EndColumn {
            get {
                if (Column == 1) {
                    return (Line == TokenBeginLine) ? 1 : GetLineLength(Line - 1);
                }
                return Column - 1;
            }
        }

        internal void GoTo(uint line, uint column) {
            _bufferPosition = GetOffset(line, column);
            Line = line;
            Column = column;
        }

        public void Backup(uint amount) {
            for (var i = 0; i < amount; i++) {
                if (Column == 1) {
                    BackupLine();
                }
                else {
                    Column--;
                    _bufferPosition--;
                }
            }
        }

        public void Forward(uint amount) {
            for (var i = 0; i < amount; i++) {
                if (Column < GetLineLength(Line)) {
                    _bufferPosition++;
                    Column++;
                }
                else {
                    AdvanceLine();
                }
            }
        }

        public void AdvanceLine() {
            var line = Line + 1;
            while (!IsParsedLine(line) && ((line - StartingLine) < _lineOffsets.Length)) {
                line++;
            }
            Line = line;
            if ((line - StartingLine) >= _lineOffsets.Length) {
                _bufferPosition = (uint) _content.Length;
            }
            else {
                _bufferPosition = GetLineStartOffset(line);
            }
            Column = 1;
        }

        public void BackupLine() {
            var line = Line - 1;
            while (!IsParsedLine(line) && (line >= StartingLine)) {
                line--;
            }
            Line = line;
            if (line < StartingLine) {
                GoTo(StartingLine, StartingColumn);
            }
            else {
                Column = GetLineLength(line);
                _bufferPosition = GetLineStartOffset(line) + Column - 1;
            }
        }

        public int ReadChar() {
            if (_bufferPosition >= _content.Length) {
                return -1;
            }
            var ch = _content[(int) _bufferPosition++];
            if (ch == '\n') {
                AdvanceLine();
            }
            else {
                Column += 1;
            }
            return ch;
        }

        public uint GetLineLength(uint lineno) {
            var startOffset = GetLineStartOffset(lineno);
            var endOffset = GetLineEndOffset(lineno);
            return 1 + endOffset - startOffset;
        }

        public uint GetLineStartOffset(uint lineno) {
            var realLineNumber = lineno - StartingLine;
            if (realLineNumber <= 0) {
                return 0;
            }
            if (realLineNumber >= _lineOffsets.Length) {
                return (uint) _content.Length;
            }
            return _lineOffsets[realLineNumber];
        }

        public uint GetLineEndOffset(uint lineno) {
            var realLineNumber = lineno - StartingLine;
            if (realLineNumber < 0) {
                return 0;
            }
            if (realLineNumber >= _lineOffsets.Length) {
                return (uint) _content.Length;
            }
            if (realLineNumber == (_lineOffsets.Length - 1)) {
                return (uint) (_content.Length - 1);
            }
            return _lineOffsets[realLineNumber + 1] - 1;
        }

        public uint GetOffset(uint line, uint column) {
            if (line == 0) {
                line = StartingLine;  // REVISIT? This should not be necessary!
            }
            var columnAdjustment = (line == StartingLine) ? StartingColumn : 1;
            return _lineOffsets[line - StartingLine] + column - columnAdjustment;
        }

        public string GetSourceLine(uint lineno) {
            var start = GetLineStartOffset(lineno);
            var end = GetLineEndOffset(lineno);
            return _content.Substring((int) start, (int) (end - start));
        }
    }
*/

    public static class Utils {

        public static void AddRange<T>(this IList<T> list1, IEnumerable<T> list2) {
            foreach (var item in list2) {
                list1.Add(item);
            }
        }

        public static void AddRange<T>(this ListAdapter<T> list1, IEnumerable<T> list2) {
            foreach (var item in list2) {
                list1.Add(item);
            }
        }

        public static HashSet<T> EnumSet<T>(params T[] values) where T : struct, Enum {
            var result = new HashSet<T>();

            foreach(T v in values) {
                result.Add(v);
            }
            return result;
        }

        public static int MaxOf(params int[] values) {
            int result = 0;

            foreach (int i in values) {
                if (result < i) {
                    result = i;
                }
            }
            return result;
        }

        internal static string DisplayChar(int ch) {
            if (ch == '\'') return "\'\\'\'";
            if (ch == '\\') return "\'\\\\\'";
            if (ch == '\t') return "\'\\t\'";
            if (ch == '\r') return "\'\\r\'";
            if (ch == '\n') return "\'\\n\'";
            if (ch == '\f') return "\'\\f\'";
            if (ch == ' ') return "\' \'";
            char c = (char) ch;
            if (c < 128 && !char.IsWhiteSpace(c) && !char.IsControl(c)) return $"\'{c}\'";
            return "0x" + ch.ToString("X4");
        }

        internal static string AddEscapes(string str) {
            StringBuilder result = new StringBuilder();
            foreach (char ch in str) {
                switch (ch) {
                case '\b':
                    result.Append("\\b");
                    continue;
                case '\t':
                    result.Append("\\t");
                    continue;
                case '\n':
                    result.Append("\\n");
                    continue;
                case '\f':
                    result.Append("\\f");
                    continue;
                case '\r':
                    result.Append("\\r");
                    continue;
                case '\"':
                    result.Append("\\\"");
                    continue;
                case '\'':
                    result.Append("\\\'");
                    continue;
                case '\\':
                    result.Append("\\\\");
                    continue;
                default:
                    if (char.IsControl(ch)) {
                        string s = ((int) ch).ToString("X4");
                        result.Append("\\u");
                        result.Append(s);
                    } else {
                        result.Append(ch);
                    }
                    continue;
                }
            }
            return result.ToString();
        }

        internal static T Pop<T>(this IList<T> list) {
            int n = list.Count - 1;
            Debug.Assert(n >= 0);
            var result = list[n];
            list.RemoveAt(n);
            return result;
        }

        private static readonly Dictionary<TokenType[], HashSet<TokenType>> SetCache = new Dictionary<TokenType[], HashSet<TokenType>>();

        public static HashSet<TokenType> GetOrMakeSet(params TokenType[] types) {
            HashSet<TokenType> result;

            if (SetCache.ContainsKey(types)) {
                result = SetCache[types];
            }
            else {
                result = EnumSet(types);
                SetCache[types] = result;
            }
            return result;
        }

        public static void AddRange<T>(this HashSet<T> set, IEnumerable<T> source) {
            foreach(T item in source) {
                set.Add(item);
            }
        }
    }

[#if unwanted!false]
    public enum LogLevel {
        DEBUG,
        INFO,
        WARNING,
        ERROR,
        CRITICAL
    }

    public class LogInfo {
        public LogLevel Level { get; private set; }
        public string Message { get; private set; }
        public object[] Arguments { get; private set; }

        public LogInfo(LogLevel level, string message, params object[] arguments) {
            Level = level;
            Message = message;
            Arguments = arguments;
        }

        public string Format() {
            return (Arguments.Length == 0) ? Message : string.Format(Message, Arguments);
        }
    }

    internal class Unsubscriber<T> : IDisposable {
        private IList<IObserver<T>>_observers;
        private IObserver<T> _observer;

        public Unsubscriber(IList<IObserver<T>> observers, IObserver<T> observer) {
            _observers = observers;
            _observer = observer;
        }

        public void Dispose() {
            if (_observer != null && _observers.Contains(_observer)) {
                _observers.Remove(_observer);
            }
        }
   }

[/#if]
    //
    // Emulation of the Java interface / implementation
    //
    public interface Iterator<T> {
        bool HasNext();
        bool HasPrevious();
        T Next();
        T Previous();
    }

    internal class ListIterator<T> : Iterator<T> {
        private readonly IList<T> _list;
        private readonly int _count;
        private int _pos;

        public ListIterator(IList<T> list, int pos = 0) {
            _list = list;
            _count = list.Count;
            Debug.Assert(pos <= _count);
            _pos = pos;
        }

        public bool HasNext() => _pos < _count;

        public bool HasPrevious() => _pos > 0;

        public T Next() {
            Debug.Assert(HasNext());
            return _list[_pos++];
        }

        public T Previous() {
            Debug.Assert(HasPrevious());
            return _list[--_pos];
        }
    }

    internal class ForwardIterator<T> {
        private readonly ListIterator<T> _iter1, _iter2;

        public ForwardIterator(IList<T> list1, IList<T> list2) {
            _iter1 = new ListIterator<T>(list1);
            _iter2 = new ListIterator<T>(list2);
        }

        public bool HasNext()  => _iter1.HasNext() || _iter2.HasNext();

        public T Next() => _iter1.HasNext() ? _iter1.Next() : _iter2.Next();

        public bool HasPrevious() => _iter2.HasPrevious() || _iter1.HasPrevious();

        public T Previous() => _iter2.HasPrevious()  ? _iter2.Previous() : _iter1.Previous();
    }

    internal class BackwardIterator<T> {
        private readonly ListIterator<T> _iter1, _iter2;

        public BackwardIterator(IList<T> list1, IList<T> list2) {
            _iter1 = new ListIterator<T>(list1, list1.Count);
            _iter2 = new ListIterator<T>(list2, list2.Count);
        }

        public bool HasNext()  => _iter2.HasPrevious() || _iter1.HasPrevious();

        public T Next() => _iter2.HasPrevious() ? _iter2.Previous() : _iter1.Previous();

        public bool HasPrevious() => _iter1.HasNext() || _iter2.HasNext();

        public T Previous() => _iter1.HasNext()  ? _iter1.Next() : _iter2.Next();
    }

    public class GenWrapper<T> : Iterator<T> {
        private IEnumerator<T> enumerator;
        private bool hasNext;

        public GenWrapper(IEnumerable<T> e) {
            enumerator = e.GetEnumerator();
            hasNext = enumerator.MoveNext();
        }

        public bool HasNext() {
            return hasNext;
        }

        public bool HasPrevious() {
            return false;
        }

        public T Next() {
            T result = enumerator.Current;
            hasNext = enumerator.MoveNext();
            return result;
        }

        public T Previous() {
            return default(T);
        }
    }

    public class ListAdapter<T> : List<T> {
        public ListAdapter() {}
        public ListAdapter(int capacity) {}
        public ListAdapter(IEnumerable<T> other) : base(other) {}

        public void Remove(int index) {
            RemoveAt(index);
        }
    }

/*
    public class SetAdapter<T> : HashSet<T> {
        public SetAdapter() : base() {}
        public SetAdapter(IEnumerable<T> source) : base(source) {}
        public void AddRange(IEnumerable<T> source) {
            foreach(T item in source) {
                Add(item);
            }
        }
    }
 */
/*

# Any stuff below is for debugging only ... to be deleted later
[#var cases = [
  "a = b ? c : d",
  "currentLookaheadToken || lastConsumedToken",
  "TokenType.STRICTFP",
  "!(getToken(1).getImage().equals(\"yield\")&&isInProduction(\"SwitchExpression\"))",
  "foo.toString()",
  "lhs.isAssignableTo()",
  "lhs.isMethodCall()||lhs.isConstructorInvocation()||lhs.isAllocation()",
  "isParserTolerant()||permissibleModifiers.contains(getToken(1).getType())",
  "currentLookaheadToken==null&&!((Expression)peekNode()).isAssignableTo()",
  "currentLookaheadToken!=null||((Expression)peekNode()).isAssignableTo()",
  "getToken(1).getType()!=TokenType._DEFAULT"
] ]
[#list cases as case]
# "${case}" -> ${grammar.utils.translateString(case)}
[/#list]
[#-- list grammar.utils.sortedNodeClassNames as cn]
# ${cn}
[/#list --]
*/
}
