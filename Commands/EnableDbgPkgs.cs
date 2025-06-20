namespace DbgPkgEnabler
{
    [Command(PackageIds.EnableDbgPkgsCommand)]
    internal sealed class EnableDbgPkgs : BaseCommand<EnableDbgPkgs>
    {
        protected override async Task ExecuteAsync(OleMenuCmdEventArgs e)
        {
            await ThreadHelper.JoinableTaskFactory.SwitchToMainThreadAsync();
            var dte = (EnvDTE.DTE)await ServiceProvider.GetGlobalServiceAsync(typeof(EnvDTE.DTE));
            var activeProject = dte?.ActiveSolutionProjects is Array projects && projects.Length > 0
                ? projects.GetValue(0) as EnvDTE.Project
                : null;

            if (activeProject != null)
            {
                string projectName = activeProject.Name;
                string preBuildEvent = activeProject.Properties.Item("PreBuildEvent")?.Value?.ToString() ?? "Not set";
                // Do something with the project
                await VS.MessageBox.ShowAsync("DbgPkgEnabler", $"Active project: {projectName}; Prebuild:\r\n{preBuildEvent}");
                activeProject.Properties.Item("PreBuildEvent").Value += $"\r\n(new command {DateTime.Now.ToShortTimeString()})";
                activeProject.Save();
            }
            else
            {
                await VS.MessageBox.ShowWarningAsync("DbgPkgEnabler", "No active project found.");
            }

            //await VS.MessageBox.ShowWarningAsync("DbgPkgEnabler", "Button clicked");
        }
    }
}
