#include <MNN/Interpreter.hpp>
#include <MNN/Tensor.hpp>

#include <algorithm>
#include <cstring>
#include <memory>
#include <string>
#include <vector>

namespace {

struct MnnContext {
  std::vector<uint8_t> model;
  std::shared_ptr<MNN::Interpreter> interpreter;
  MNN::Session* session = nullptr;
  MNN::Tensor* input = nullptr;
  MNN::Tensor* output = nullptr;
  int requested_backend = 0;
  std::string error;
};

thread_local std::string last_error;

void set_error(MnnContext* context, const std::string& message) {
  last_error = message;
  if (context != nullptr) {
    context->error = message;
  }
}

}  // namespace

extern "C" __attribute__((visibility("default"))) void*
aicamera_mnn_create(const uint8_t* model_data, intptr_t model_size,
                    int32_t threads, int32_t backend, int32_t low_precision) {
  if (model_data == nullptr || model_size <= 0) {
    set_error(nullptr, "MNN model buffer is empty.");
    return nullptr;
  }

  auto context = std::make_unique<MnnContext>();
  context->model.assign(model_data, model_data + model_size);
  context->requested_backend = backend;
  context->interpreter.reset(MNN::Interpreter::createFromBuffer(
      context->model.data(), context->model.size()));
  if (!context->interpreter) {
    set_error(context.get(), "MNN failed to parse the model.");
    return nullptr;
  }

  MNN::ScheduleConfig config;
  config.numThread = std::max(1, threads);
  config.type =
      backend == 3 ? MNN_FORWARD_OPENCL : MNN_FORWARD_CPU;

  MNN::BackendConfig backend_config;
  backend_config.precision = low_precision != 0
                                 ? MNN::BackendConfig::Precision_Low
                                 : MNN::BackendConfig::Precision_Normal;
  backend_config.memory = MNN::BackendConfig::Memory_Low;
  config.backendConfig = &backend_config;

  context->session = context->interpreter->createSession(config);
  if (context->session == nullptr) {
    set_error(context.get(), "MNN failed to create the inference session.");
    return nullptr;
  }
  context->input = context->interpreter->getSessionInput(context->session, nullptr);
  context->output =
      context->interpreter->getSessionOutput(context->session, nullptr);
  if (context->input == nullptr || context->output == nullptr) {
    set_error(context.get(), "MNN model input or output tensor is missing.");
    return nullptr;
  }
  const bool input_shape_matches =
      context->input->dimensions() == 4 &&
      context->input->length(0) == 1 &&
      context->input->length(1) == 3 &&
      context->input->length(2) == 320 &&
      context->input->length(3) == 320;
  const bool output_shape_matches =
      context->output->dimensions() == 3 &&
      context->output->length(0) == 1 &&
      context->output->length(1) == 84 &&
      context->output->length(2) == 2100;
  if (!input_shape_matches || !output_shape_matches) {
    set_error(
        context.get(),
        "MNN model shape must be [1,3,320,320] -> [1,84,2100].");
    return nullptr;
  }
  return context.release();
}

extern "C" __attribute__((visibility("default"))) int32_t
aicamera_mnn_run(void* handle, const float* input_data, intptr_t input_count,
                 float* output_data, intptr_t output_count) {
  auto* context = static_cast<MnnContext*>(handle);
  if (context == nullptr || input_data == nullptr || output_data == nullptr) {
    set_error(context, "MNN run received a null argument.");
    return -1;
  }
  if (context->input->elementSize() != input_count) {
    set_error(context, "MNN input tensor element count does not match.");
    return -2;
  }
  if (context->output->elementSize() != output_count) {
    set_error(context, "MNN output tensor element count does not match.");
    return -3;
  }

  // Keep the converted model's original dimension type. The source TFLite
  // tensor has an NCHW-shaped raw buffer even though MNN records the default
  // model dimension format as NHWC; requesting CAFFE here would transpose the
  // buffer a second time.
  MNN::Tensor input_host(
      context->input, context->input->getDimensionType());
  std::memcpy(input_host.host<float>(), input_data,
              static_cast<size_t>(input_count) * sizeof(float));
  context->input->copyFromHostTensor(&input_host);

  const auto code = context->interpreter->runSession(context->session);
  if (code != MNN::NO_ERROR) {
    set_error(context, "MNN session execution failed with code " +
                           std::to_string(static_cast<int>(code)) + ".");
    return -4;
  }

  MNN::Tensor output_host(
      context->output, context->output->getDimensionType());
  context->output->copyToHostTensor(&output_host);
  std::memcpy(output_data, output_host.host<float>(),
              static_cast<size_t>(output_count) * sizeof(float));
  return 0;
}

extern "C" __attribute__((visibility("default"))) int32_t
aicamera_mnn_requested_backend(void* handle) {
  auto* context = static_cast<MnnContext*>(handle);
  return context == nullptr ? -1 : context->requested_backend;
}

extern "C" __attribute__((visibility("default"))) const char*
aicamera_mnn_last_error(void* handle) {
  auto* context = static_cast<MnnContext*>(handle);
  if (context != nullptr && !context->error.empty()) {
    return context->error.c_str();
  }
  return last_error.c_str();
}

extern "C" __attribute__((visibility("default"))) void
aicamera_mnn_destroy(void* handle) {
  auto* context = static_cast<MnnContext*>(handle);
  if (context == nullptr) {
    return;
  }
  if (context->interpreter && context->session != nullptr) {
    context->interpreter->releaseSession(context->session);
  }
  delete context;
}
