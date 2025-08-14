using System.Diagnostics;
using System.IO;

namespace DbgPkgEnabler
{
    internal class FileTraceListener : TraceListener
    {
        private readonly StreamWriter _writer;

        /// <summary>
        /// Initializes a new instance of the <see cref="FileTraceListener"/> class that writes trace information to a
        /// specified file.
        /// </summary>
        /// <param name="filePath">The path of the file to which trace information will be written</param>
        public FileTraceListener(string filePath)
        {
            _writer = new StreamWriter(filePath, append: true) { AutoFlush = true };
        }

        /// <summary>
        /// Overrides the <see cref="TraceListener"/> Write method to write a message to the trace output.
        /// </summary>
        /// <param name="message"></param>
        public override void Write(string message) => _writer.Write(message);

        /// <summary>
        /// Overrides the <see cref="TraceListener"/> WriteLine method to write a message followed by a line terminator to the trace output.
        /// </summary>
        /// <param name="message"></param>
        public override void WriteLine(string message) => _writer.WriteLine(message);

        /// <summary>
        /// overrides the <see cref="TraceListener"/> TraceEvent method. It ignores the ID parameter if it's not null.
        /// </summary>
        public override void TraceEvent(TraceEventCache eventCache, string source, TraceEventType eventType, int id, string message)
        {
            string eventTypeName = eventType switch
            {
                TraceEventType.Critical    => "crit",
                TraceEventType.Error       => "err",
                TraceEventType.Warning     => "warn",
                TraceEventType.Information => "info",
                TraceEventType.Verbose     => "vbs",
                _ => eventType.ToString()
            };

            //string timestamp = eventCache?.Timestamp.ToString("yyyy-MM-dd HH:mm:ss.fff") ?? DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss.fff");
            string timestamp = DateTime.Now.ToString("yy.MM.dd/HH:mm:ss.fff");
            // Format without including 'id' if it is zero
            if (id == 0)
                WriteLine($"{source} ({timestamp}) {message}");
            else
                WriteLine($"{source} ({timestamp} : /{id}) {message}");
        }

        /// <summary>
        /// Just dispose the writer
        /// </summary>
        /// <param name="disposing"></param>
        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                _writer?.Dispose();
            }
            base.Dispose(disposing);
        }
    }
}
