import SwiftUI

struct ResultView: View {
    let text: String

    var body: some View {
        ScrollView {
            Text(text)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Ответ")
    }
}

struct ResultView_Previews: PreviewProvider {
    static var previews: some View {
        ResultView(text: "Пример ответа")
    }
}
