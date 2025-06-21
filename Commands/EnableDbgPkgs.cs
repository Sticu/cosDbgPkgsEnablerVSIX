using System.Diagnostics;
using System.IO;

namespace DbgPkgsEnabler
{
    [Command(PackageIds.EnableDbgPkgsCommand)]
    internal sealed class EnableDbgPkgs : BaseCommand<EnableDbgPkgs>
    {
        // Create a TraceSource instance for this class
        private static readonly TraceSource _trace = new TraceSource("[DbgPkgsEnabler]");

        static EnableDbgPkgs()
        {
            //_trace.Listeners.Add(new DefaultTraceListener()); //-not needed
            if (_trace.Listeners.Count == 1 && _trace.Listeners[0] is DefaultTraceListener)
            {
                // Output to Debug window
                //_trace.Listeners.Add(new TextWriterTraceListener(Console.Out, "debug"));

                // Optional: Output to a file
                string logFileName = $"DbgPkgsEnabler-{DateTime.Now.ToString("yyyyMMddHHmmss")}.log";
                string logFilePath = Path.Combine(Path.GetTempPath(), logFileName);
                _trace.Listeners.Add(new TextWriterTraceListener(logFilePath));
            }
            _trace.Switch.Level = SourceLevels.All;
        }

        protected override async Task ExecuteAsync(OleMenuCmdEventArgs e)
        {
            _trace.TraceEvent(TraceEventType.Information, 1, "Enabler started...");

            await ThreadHelper.JoinableTaskFactory.SwitchToMainThreadAsync();
            _trace.TraceInformation("asta e info Enabler started");

            var dte = (EnvDTE.DTE)await ServiceProvider.GetGlobalServiceAsync(typeof(EnvDTE.DTE));
            _trace.TraceEvent(TraceEventType.Information, 2, "Retrieved DTE service");

            var activeProject = dte?.ActiveSolutionProjects is Array projects && projects.Length > 0
                ? projects.GetValue(0) as EnvDTE.Project
                : null;

            if (activeProject != null)
            {
                string projectName = activeProject.Name;
                _trace.TraceEvent(TraceEventType.Information, 3, $"Found active project: {projectName}");

                string preBuildEvent = activeProject.Properties.Item("PreBuildEvent")?.Value?.ToString() ?? "Not set";
                _trace.TraceEvent(TraceEventType.Information, 4, $"Current PreBuildEvent: {preBuildEvent}");

                // Do something with the project
                await VS.MessageBox.ShowAsync("DbgPkgsEnabler", $"Active project: {projectName}; Prebuild:\r\n{preBuildEvent}");

                activeProject.Properties.Item("PreBuildEvent").Value += $"\r\nREM (new command {DateTime.Now.ToShortTimeString()})";
                _trace.TraceEvent(TraceEventType.Information, 5, "Updated PreBuildEvent");

                activeProject.Save();
                _trace.TraceEvent(TraceEventType.Information, 6, "Saved project");
            }
            else
            {
                _trace.TraceEvent(TraceEventType.Warning, 7, "No active project found");
                await VS.MessageBox.ShowWarningAsync("DbgPkgsEnabler", "No active project found.");
            }

            _trace.TraceEvent(TraceEventType.Information, 8, "...Enabler completed");
        }
    }
}
