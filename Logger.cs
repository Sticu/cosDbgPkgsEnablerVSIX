using System.Diagnostics;
using System.IO;

namespace DbgPkgEnabler
{
    public static class Logger
    {
        // Create a TraceSource instance for this class
        private static readonly TraceSource _logger = new TraceSource("[dbgpkgsEnabler]");

        /// <summary>
        /// Initializes the <see cref="Logger"/> class by configuring its trace listeners and setting the default
        /// logging level.
        /// </summary>
        /// <remarks>
        /// This static constructor configures a set of trace listeners for outputting log messages.
        /// Beside the default <see cref="DefaultTraceListener"/>,  additional listeners are added:
        /// a <see cref="ConsoleTraceListener"/> for console output
        /// and a <see cref="FileTraceListener"/> for writing logs to a file in the temporary folder.
        /// </remarks>
        static Logger()
        {
            if (_logger.Listeners.Count == 1 && _logger.Listeners[0] is DefaultTraceListener)
            {
                // Add a console listener for debugging purposes
                _logger.Listeners.Add(new ConsoleTraceListener());

                string logFileName = $"dbgPkgsEnabler-{DateTime.Now:yyyyMMdd.HHmmss}.log";
                string logFilePath = Path.Combine(Path.GetTempPath(), logFileName);

                // Output to a file -> superseeded by the to-file listener below
                //_logger.Listeners.Add(new TextWriterTraceListener(logFilePath));

                _logger.Listeners.Add(new FileTraceListener(logFilePath));
                //_logger.Switch = new SourceSwitch("sourceSwitch", "Verbose");
            }

            // Set the default level to ALL
            _logger.Switch.Level = SourceLevels.All;
        }

        /// <summary>
        /// Log an info message
        /// </summary>
        /// <param name="message"></param>
        /// <param name="id"></param>
        public static void LogInfo(string message, int id = 0)
        {
            _logger.TraceEvent(TraceEventType.Information, id, message);
        }
    }
}
