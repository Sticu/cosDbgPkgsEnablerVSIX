using DbgPkgEnabler;
using Microsoft.VisualStudio.PlatformUI;
using System.IO;

namespace DbgPkgsEnabler
{
    [Command(PackageIds.EnableDbgPkgsCommand)]
    internal sealed class EnableDbgPkgs : BaseCommand<EnableDbgPkgs>
    {
        static EnableDbgPkgs()
        {
        }

        /// <summary>
        /// This method is called when the menu command is executed.
        /// </summary>
        protected override async Task ExecuteAsync(OleMenuCmdEventArgs e)
        {
            Logger.LogInfo( "Enabler started |->...");

            await ThreadHelper.JoinableTaskFactory.SwitchToMainThreadAsync();

            var dte = (EnvDTE.DTE)await ServiceProvider.GetGlobalServiceAsync(typeof(EnvDTE.DTE));
            Logger.LogInfo("Retrieved DTE service");

            var activeProject = dte?.ActiveSolutionProjects is Array projects && projects.Length > 0
                ? projects.GetValue(0) as EnvDTE.Project
                : null;

            if (activeProject != null)
            {
                string projectName = activeProject.UniqueName;
                Logger.LogInfo($"Found active project: {projectName}");

                string preBuildEvent = activeProject.Properties.Item("PreBuildEvent")?.Value?.ToString() ?? "Not set";
                Logger.LogInfo($"Current PreBuildEvent: {preBuildEvent}");

                activeProject.Properties.Item("PreBuildEvent").Value += $"\r\nREM (new command {DateTime.Now.ToShortTimeString()})";
                Logger.LogInfo("Updated PreBuildEvent");

                activeProject.Save();
                Logger.LogInfo("Project saved.");

                preBuildEvent = activeProject.Properties.Item("PreBuildEvent")?.Value?.ToString() ?? "Not set";

                // Do something with the project
                //await VS.MessageBox.ShowAsync("DbgPkgsEnabler", $"Active project: {projectName}; Prebuild:\r\n{preBuildEvent}");
                //-		dialog	{Microsoft.VisualStudio.PlatformUI.DialogWindow}	Microsoft.VisualStudio.PlatformUI.DialogWindow

                var dialog = new ProgressDlg(projectName);
                dialog.HasMinimizeButton = false;
                dialog.HasMaximizeButton = true;
                dialog.IsCloseButtonEnabled = false;
                dialog.Title = "Debug NuGet Packages Enabler";
                dialog.ShowModal();

                //string dropFilePath = Path.Combine(Path.GetDirectoryName(activeProject.FullName), "xscript.kk");
                //File.WriteAllText(dropFilePath, activeProject.FullName);
                //activeProject.ProjectItems.AddFromFile(dropFilePath);
                //activeProject.Save();
            }
            else
            {
                Logger.LogInfo("No active project found");
                await VS.MessageBox.ShowWarningAsync("DbgPkgsEnabler", "No active project found.");
            }

            Logger.LogInfo("...Enabler completed->|");
        }
    }
}
