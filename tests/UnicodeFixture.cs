using System;
using System.Text.Json;
using System.Text.Json.Serialization;

// Ordinary public JSON-helper consumers only; no transport/provider replacement.
public sealed class UnicodeCountedValue {
    public int Reads;
    public string Text { get { Reads++; return "valid-\ufffd-\U0001f642"; } }
}
[JsonConverter(typeof(UnicodeCountedConverter))]
public sealed class UnicodeConvertedValue {
    public int Writes;
    public string Text { get; set; } = "valid-\ufffd-\U0001f642";
}
public sealed class UnicodeCountedConverter:JsonConverter<UnicodeConvertedValue> {
    public override UnicodeConvertedValue Read(ref Utf8JsonReader reader,Type type,JsonSerializerOptions options)=>throw new NotSupportedException();
    public override void Write(Utf8JsonWriter writer,UnicodeConvertedValue value,JsonSerializerOptions options){
        value.Writes++;writer.WriteStartObject();writer.WriteString("text",value.Text);writer.WriteEndObject();
    }
}
