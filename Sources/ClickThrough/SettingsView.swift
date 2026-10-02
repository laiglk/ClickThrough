import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "cursorarrow.click.2")
                    .font(.system(size: 32)).foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("ClickThrough").font(.title2.bold())
                    Text("Un clic. L’action voulue.").foregroundStyle(.secondary)
                }
                Spacer()
                Label(model.status, systemImage: model.running ? "checkmark.circle.fill" : "pause.circle")
                    .font(.callout).foregroundStyle(model.running ? Color.accentColor : .secondary)
            }
            .padding(24)
            Divider()
            Form {
                if !model.trusted {
                    Section("Autoriser ClickThrough") {
                        Text("L’accès à l’accessibilité permet d’activer la fenêtre visée et de lui transmettre votre clic. Tout reste sur ce Mac.")
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Ouvrir les réglages d’accessibilité…") { model.requestAccess() }
                            .buttonStyle(.borderedProminent)
                        Button("Vérifier l’autorisation maintenant") { model.verifyAccess() }
                            .buttonStyle(.bordered)
                        Text("Copie actuellement lancée : \(model.applicationPath)")
                            .font(.caption).textSelection(.enabled)
                        Text("Dans Réglages Système › Confidentialité et sécurité › Accessibilité, désactivez puis supprimez l’ancienne entrée ClickThrough avec −. Ajoutez ensuite le fichier indiqué ci-dessus avec +, activez-le, quittez ClickThrough et relancez cette même copie.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section {
                    Toggle("Activer le premier clic", isOn: $model.enabled)
                    Toggle("Lancer à l’ouverture de session", isOn: Binding(
                        get: { model.loginEnabled || model.loginNeedsApproval }, set: model.setLogin))
                    if model.loginNeedsApproval {
                        Button("Autoriser dans les éléments d’ouverture…") { model.openLoginSettings() }
                    }
                } header: { Text("Général") } footer: {
                    Text("Le clic gauche active la fenêtre et réalise l’action. Les clics avec ⌘, ⌃, ⌥ ou ⇧ conservent le comportement de macOS.")
                }
                Section {
                    if model.exclusions.isEmpty {
                        Text("Aucune exclusion. Ajoutez une application pour y conserver le comportement habituel de macOS.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.exclusions) { app in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(app.name)
                                Text(app.id).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button { model.removeExclusion(app) } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Retirer l’exclusion de \(app.name)")
                            .help("Réactiver ClickThrough pour \(app.name)")
                        }
                    }
                    Button("Ajouter une application…", systemImage: "plus") { model.addExclusion() }
                } header: { Text("Applications exclues") }
                Section("État du prototype") {
                    LabeledContent("Clics transmis après activation", value: "\(model.processedClicks) cette session")
                    Text("ChatGPT, Firefox, Finder et Anytype sont les applications prioritaires à tester. La compatibilité dépend de chaque fenêtre.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let notice = model.notice {
                        Text(notice).font(.callout).textSelection(.enabled)
                        Button("Effacer le message") { model.notice = nil }
                    }
                    if model.trusted && model.enabled && !model.running {
                        Button("Réessayer") { model.refresh() }
                        Text("Si le problème persiste, quittez puis relancez ClickThrough après avoir vérifié son autorisation d’accessibilité.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(minWidth: 570, idealWidth: 610, minHeight: 580, idealHeight: 680)
    }
}
