# YOLOv8n 320 TFLite

## 模型信息

- 文件：`yolov8n_320.tflite`
- 来源权重：Ultralytics 官方 `yolov8n.pt`
- 导出工具：Ultralytics 8.4.112
- 输入：Float32 NCHW `[1, 3, 320, 320]`，RGB，取值范围 0～1
- 输出：Float32 `[1, 84, 2100]`；框为相对模型输入归一化的 `cxcywh`
- 类别：COCO 80 类
- SHA-256：`f8ae952090cd2c016304b9b2abf953aa03f3dd1368199ff773b9377b3be35443`

导出设置：

```python
from ultralytics import YOLO

YOLO("yolov8n.pt").export(
    format="tflite",
    imgsz=320,
    nms=False,
    end2end=False,
)
```

应用侧执行等比例 letterbox（填充值 114）、RGB 归一化、类别级 NMS，
因此替换模型时必须同步核对输入布局、输出布局、类别表和归一化方式。

## 许可证提示

模型来自 Ultralytics YOLOv8 项目。Ultralytics 提供 AGPL-3.0 和企业许可
选项；该模型仅用于当前技术预研。接入闭源或商业业务前，应由团队确认
适用许可证，必要时更换为已获授权的业务模型。
