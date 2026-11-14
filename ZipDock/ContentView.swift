import SwiftUI
import UniformTypeIdentifiers

enum Operation: String, CaseIterable, Identifiable {
    case compress = "В ZIP"
    case extract = "Из ZIP"
    case split = "Разделить"
    case join = "Собрать"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .compress: "archivebox.fill"
        case .extract: "shippingbox.fill"
        case .split: "square.split.2x2.fill"
        case .join: "square.stack.3d.up.fill"
        }
    }
    var detail: String {
        switch self {
        case .compress: "Создать ZIP из файла или папки"
        case .extract: "Распаковать ZIP в отдельную папку"
        case .split: "Разбить большой файл на части"
        case .join: "Объединить все .part001, .part002…"
        }
    }
}

struct ContentView: View {
    @State private var operation: Operation = .split
    @State private var partSize = 50
    @State private var picking = false
    @State private var pickingFolder = false
    @State private var working = false
    @State private var results: [OutputFile] = []
    @State private var status = ""
    @State private var errorText: String?
    private let sizes = [20, 50, 100, 200]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 25) {
                    header
                    VStack(spacing: 10) {
                        ForEach(Operation.allCases) { op in
                            Button {
                                operation = op
                                results = []
                                status = ""
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: op.symbol)
                                        .font(.system(size: 21, weight: .semibold))
                                        .frame(width: 45, height: 45)
                                        .background(operation == op ? Color.indigo : Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 13))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(op.rawValue).font(.headline)
                                        Text(op.detail).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 5)
                                    if operation == op { Image(systemName: "checkmark.circle.fill").foregroundStyle(.indigo) }
                                }
                                .foregroundStyle(.white)
                                .padding(13)
                                .background(Color.white.opacity(operation == op ? 0.11 : 0.05), in: RoundedRectangle(cornerRadius: 18))
                            }
                            .buttonStyle(.plain)
                            .disabled(working)
                        }
                    }

                    if operation == .split {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("РАЗМЕР ЧАСТИ").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                            Picker("Размер части", selection: $partSize) {
                                ForEach(sizes, id: \.self) { size in Text("\(size) МБ").tag(size) }
                            }
                            .pickerStyle(.segmented)
                            Text("Для отправки TikTok IPA удобно выбрать 50 МБ. Части не сжимаются, а режутся по байтам без потерь.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }

                    Button { pickingFolder = false; picking = true } label: {
                        HStack {
                            Spacer()
                            if working { ProgressView().tint(.white) }
                            else { Image(systemName: "doc.badge.plus") }
                            Text(working ? "Обрабатываем…" : operation == .join ? "Выбрать все части" : "Выбрать файл")
                            Spacer()
                        }
                        .font(.headline)
                        .padding(18)
                        .background(Color.indigo, in: RoundedRectangle(cornerRadius: 17))
                    }
                    .disabled(working)
                    .foregroundStyle(.white)

                    if operation == .compress {
                        Button("Выбрать папку") { pickingFolder = true; picking = true }
                            .disabled(working)
                    }

                    if !status.isEmpty { Text(status).font(.subheadline).foregroundStyle(.secondary) }
                    if !results.isEmpty { resultSection }
                    footer
                }
                .padding(20)
            }
            .background(Color(red: 0.055, green: 0.06, blue: 0.09))
            .navigationBarHidden(true)
        }
        .fileImporter(isPresented: $picking,
                      allowedContentTypes: pickingFolder ? [.folder] : [.data],
                      allowsMultipleSelection: !pickingFolder && operation == .join) { result in
            switch result {
            case .success(let urls): process(urls)
            case .failure(let error): errorText = error.localizedDescription
            }
        }
        .alert("Ошибка", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("Понятно", role: .cancel) { errorText = nil }
        } message: { Text(errorText ?? "Неизвестная ошибка") }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 12) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.title2).foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Color.indigo, in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 2) {
                    Text("ZipDock").font(.system(size: 29, weight: .bold, design: .rounded))
                    Text("Архивы и большие файлы").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Text("Без сервера. Без загрузки в облако. Все операции — на устройстве.")
                .font(.footnote).foregroundStyle(.secondary)
                .padding(.top, 6)
        }
    }

    private var resultSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ГОТОВО · \(results.count) \(results.count == 1 ? "ОБЪЕКТ" : "ОБЪЕКТОВ")")
                .font(.caption.weight(.bold)).foregroundStyle(.secondary)
            ForEach(results) { file in
                HStack(spacing: 11) {
                    Image(systemName: "doc.zipper").foregroundStyle(.indigo)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(file.name).font(.subheadline.weight(.semibold)).lineLimit(2)
                        Text(file.size).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    ShareLink(item: file.url) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.headline)
                            .frame(width: 42, height: 42)
                            .background(Color.indigo.opacity(0.22), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .tint(.white)
                }
                .padding(11)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
            }
            Text("Нажми на значок отправки у каждой части. Все результаты также лежат в «Файлы» → «На iPhone» → ZipDock → «Результаты».")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("КАК ЭТО РАБОТАЕТ").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            Text("ZIP может почти не уменьшить размер IPA — это нормально. «Разделить» создаёт файлы .part001, .part002 и так далее. Выбирай их все в режиме «Собрать», чтобы восстановить исходный файл без изменений.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.top, 6)
    }

    private func process(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        working = true
        results = []
        status = "Подготавливаем файлы…"
        let op = operation
        let mb = partSize
        Task.detached(priority: .userInitiated) {
            do {
                let svc = ArchiveService.shared
                let inputs = try urls.map { try svc.importedCopy($0) }
                let outputs: [OutputFile]
                switch op {
                case .compress: outputs = try svc.zip(inputs[0])
                case .extract: outputs = try svc.unzip(inputs[0])
                case .split: outputs = try svc.split(inputs[0], megabytes: mb)
                case .join: outputs = try svc.join(inputs)
                }
                await MainActor.run {
                    results = outputs
                    status = "Готово. Файлы сохранены локально."
                    working = false
                }
            } catch {
                await MainActor.run {
                    working = false
                    status = ""
                    errorText = error.localizedDescription
                }
            }
        }
    }
}
