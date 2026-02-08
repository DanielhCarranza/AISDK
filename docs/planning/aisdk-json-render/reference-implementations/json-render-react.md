# json-render React Integration Guide

This document covers the React-specific components and hooks provided by `@json-render/react`.

## Table of Contents

- [Overview](#overview)
- [Renderer Component](#renderer-component)
- [JSONUIProvider](#jsonuiprovider)
- [useUIStream Hook](#useuistream-hook)
- [Data Hooks](#data-hooks)
- [Action Hooks](#action-hooks)
- [Visibility Hooks](#visibility-hooks)
- [Validation Hooks](#validation-hooks)
- [Context Providers](#context-providers)
- [Component Registry](#component-registry)
- [Advanced Patterns](#advanced-patterns)

## Overview

The `@json-render/react` package provides React bindings for json-render:

```typescript
import {
  // Core components
  Renderer,
  JSONUIProvider,

  // Streaming
  useUIStream,

  // Data access
  useData,
  useDataValue,
  useDataBinding,

  // Actions
  useActions,
  useAction,

  // Visibility
  useVisibility,
  useIsVisible,

  // Validation
  useValidation,
  useFieldValidation,

  // Types
  ComponentRegistry,
  ComponentProps,
} from '@json-render/react';
```

## Renderer Component

The `Renderer` component transforms a UI tree into React elements.

### Basic Usage

```tsx
import { Renderer } from '@json-render/react';

function App() {
  const ui = {
    type: 'card',
    title: 'Welcome',
    children: [
      { type: 'text', text: 'Hello, world!' },
    ],
  };

  return <Renderer tree={{ ui }} />;
}
```

### Props

| Prop | Type | Description |
|------|------|-------------|
| `tree` | `UITree` | The UI tree to render |
| `components` | `ComponentRegistry` | Component implementations (optional if using provider) |
| `fallback` | `ReactNode` | Rendered when tree is null/undefined |
| `errorBoundary` | `boolean` | Wrap each element in error boundary (default: true) |
| `onError` | `(error: Error, element: UIElement) => void` | Error callback |

### With Error Handling

```tsx
<Renderer
  tree={ui}
  fallback={<div>Loading...</div>}
  onError={(error, element) => {
    console.error(`Error rendering ${element.type}:`, error);
  }}
/>
```

## JSONUIProvider

The `JSONUIProvider` wraps your app with all necessary contexts.

### Basic Setup

```tsx
import { JSONUIProvider, Renderer } from '@json-render/react';

function App() {
  return (
    <JSONUIProvider
      components={myComponents}
      catalog={myCatalog}
      onAction={handleAction}
    >
      <Renderer tree={ui} />
    </JSONUIProvider>
  );
}
```

### Props

| Prop | Type | Description |
|------|------|-------------|
| `components` | `ComponentRegistry` | Component implementations |
| `catalog` | `Catalog` | Component/action catalog |
| `data` | `Record<string, unknown>` | Initial data model |
| `onAction` | `ActionHandler` | Action callback |
| `onValidationError` | `ValidationErrorHandler` | Validation error callback |
| `auth` | `AuthContext` | Authentication context for visibility |
| `children` | `ReactNode` | Child elements |

### Full Configuration

```tsx
<JSONUIProvider
  components={components}
  catalog={catalog}
  data={{
    user: { name: 'John', role: 'admin' },
    products: [],
  }}
  auth={{
    isAuthenticated: true,
    roles: ['admin', 'user'],
  }}
  onAction={async (action, payload) => {
    switch (action) {
      case 'submit':
        await submitForm(payload);
        break;
      case 'navigate':
        router.push(payload.url);
        break;
    }
  }}
  onValidationError={(fieldName, errors) => {
    console.log(`Validation errors for ${fieldName}:`, errors);
  }}
>
  <YourApp />
</JSONUIProvider>
```

## useUIStream Hook

The `useUIStream` hook manages streaming UI updates from an API endpoint.

### Basic Usage

```tsx
import { useUIStream } from '@json-render/react';

function ChatUI() {
  const { ui, isLoading, error, sendMessage } = useUIStream('/api/chat');

  return (
    <div>
      <input onKeyDown={(e) => {
        if (e.key === 'Enter') {
          sendMessage(e.currentTarget.value);
        }
      }} />

      {isLoading && <div>Loading...</div>}
      {error && <div>Error: {error.message}</div>}

      <Renderer tree={ui} />
    </div>
  );
}
```

### Return Value

```typescript
interface UseUIStreamResult {
  // Current UI tree state
  ui: UITree | null;

  // Loading state
  isLoading: boolean;

  // Error state
  error: Error | null;

  // Send a message to trigger new UI
  sendMessage: (message: string) => Promise<void>;

  // Append to existing conversation
  appendMessage: (message: string) => Promise<void>;

  // Reset UI state
  reset: () => void;

  // Abort current stream
  abort: () => void;
}
```

### With Custom Fetch Options

```tsx
const { ui, sendMessage } = useUIStream('/api/chat', {
  // Custom headers
  headers: {
    'Authorization': `Bearer ${token}`,
  },

  // Custom body transformer
  bodyTransformer: (message, history) => ({
    messages: [...history, { role: 'user', content: message }],
    model: 'gpt-4o',
  }),

  // Event callbacks
  onStart: () => console.log('Stream started'),
  onPatch: (patch) => console.log('Received patch:', patch),
  onComplete: () => console.log('Stream complete'),
  onError: (error) => console.error('Stream error:', error),
});
```

### With Message History

```tsx
function Chat() {
  const [history, setHistory] = useState<Message[]>([]);

  const { ui, sendMessage, isLoading } = useUIStream('/api/chat', {
    bodyTransformer: (message) => ({
      messages: [...history, { role: 'user', content: message }],
    }),
    onComplete: (result) => {
      setHistory(prev => [
        ...prev,
        { role: 'user', content: result.userMessage },
        { role: 'assistant', content: result.response },
      ]);
    },
  });

  return (
    <div>
      {history.map((msg, i) => (
        <div key={i} className={msg.role}>{msg.content}</div>
      ))}
      <Renderer tree={ui} />
    </div>
  );
}
```

## Data Hooks

### useData

Access the entire data model:

```tsx
import { useData } from '@json-render/react';

function DataViewer() {
  const { data, setData, updateData } = useData();

  return (
    <div>
      <pre>{JSON.stringify(data, null, 2)}</pre>
      <button onClick={() => updateData('/counter', (c) => (c || 0) + 1)}>
        Increment
      </button>
    </div>
  );
}
```

### useDataValue

Access and update a specific data path:

```tsx
import { useDataValue } from '@json-render/react';

function UserName() {
  const [name, setName] = useDataValue<string>('/user/name');

  return (
    <input
      value={name || ''}
      onChange={(e) => setName(e.target.value)}
      placeholder="Enter name"
    />
  );
}
```

### useDataBinding

Resolve dynamic values against the data model:

```tsx
import { useDataBinding } from '@json-render/react';

function DynamicText({ text }: { text: string | { $data: string } }) {
  const resolvedText = useDataBinding(text);
  return <span>{resolvedText}</span>;
}
```

### Data Path Patterns

```tsx
// Simple path
const [value] = useDataValue('/user/email');

// Array index
const [firstItem] = useDataValue('/items/0');

// With default value
const [count] = useDataValue('/counter', 0);

// Type-safe
const [user] = useDataValue<User>('/user');
```

## Action Hooks

### useActions

Get the action dispatcher:

```tsx
import { useActions } from '@json-render/react';

function MyButton() {
  const dispatch = useActions();

  const handleClick = () => {
    dispatch('submit', {
      formData: { name: 'John' },
    });
  };

  return <button onClick={handleClick}>Submit</button>;
}
```

### useAction

Get a dispatcher for a specific action:

```tsx
import { useAction } from '@json-render/react';

function NavigateButton({ url }: { url: string }) {
  const navigate = useAction('navigate');

  return (
    <button onClick={() => navigate({ url })}>
      Go to {url}
    </button>
  );
}
```

### Action with Confirmation

```tsx
import { useAction } from '@json-render/react';

function DeleteButton({ itemId }: { itemId: string }) {
  const deleteItem = useAction('delete');

  const handleDelete = async () => {
    await deleteItem(
      { itemId },
      {
        confirm: {
          title: 'Delete Item?',
          message: 'This action cannot be undone.',
          confirmLabel: 'Delete',
          cancelLabel: 'Cancel',
        },
      }
    );
  };

  return <button onClick={handleDelete}>Delete</button>;
}
```

### Action with Optimistic Updates

```tsx
function LikeButton({ postId }: { postId: string }) {
  const [liked, setLiked] = useDataValue<boolean>(`/posts/${postId}/liked`);
  const like = useAction('like');

  const handleLike = async () => {
    // Optimistic update
    setLiked(!liked);

    try {
      await like({ postId, liked: !liked });
    } catch (error) {
      // Rollback on error
      setLiked(liked);
    }
  };

  return (
    <button onClick={handleLike}>
      {liked ? '❤️' : '🤍'}
    </button>
  );
}
```

## Visibility Hooks

### useVisibility

Access visibility context:

```tsx
import { useVisibility } from '@json-render/react';

function ConditionalContent() {
  const { evaluateRule, auth } = useVisibility();

  const isAdmin = evaluateRule({ $auth: ['admin'] });
  const hasData = evaluateRule({ $data: '/user/profile' });

  return (
    <div>
      {isAdmin && <AdminPanel />}
      {hasData && <ProfileCard />}
    </div>
  );
}
```

### useIsVisible

Check visibility of a specific rule:

```tsx
import { useIsVisible } from '@json-render/react';

function AdminButton() {
  const isVisible = useIsVisible({ $auth: ['admin', 'moderator'] });

  if (!isVisible) return null;
  return <button>Admin Action</button>;
}
```

### Visibility Rule Examples

```tsx
// Based on data existence
const hasUser = useIsVisible({ $data: '/user' });

// Based on auth roles
const isAdmin = useIsVisible({ $auth: ['admin'] });

// Combined with AND
const canEdit = useIsVisible({
  $and: [
    { $auth: ['editor'] },
    { $data: '/post/draft' },
  ],
});

// Combined with OR
const canView = useIsVisible({
  $or: [
    { $auth: ['admin'] },
    { $data: '/post/published' },
  ],
});

// Negation
const isGuest = useIsVisible({
  $not: { $data: '/user' },
});
```

## Validation Hooks

### useValidation

Access the validation context:

```tsx
import { useValidation } from '@json-render/react';

function FormStatus() {
  const { errors, isValid, validate, clearErrors } = useValidation();

  return (
    <div>
      {!isValid && (
        <div className="errors">
          {Object.entries(errors).map(([field, messages]) => (
            <div key={field}>
              {field}: {messages.join(', ')}
            </div>
          ))}
        </div>
      )}
      <button onClick={clearErrors}>Clear Errors</button>
    </div>
  );
}
```

### useFieldValidation

Validate a specific field:

```tsx
import { useFieldValidation } from '@json-render/react';

function EmailInput() {
  const { value, error, validate, setTouched } = useFieldValidation(
    'email',
    ['required', 'email']
  );

  return (
    <div>
      <input
        value={value}
        onChange={(e) => validate(e.target.value)}
        onBlur={() => setTouched(true)}
      />
      {error && <span className="error">{error}</span>}
    </div>
  );
}
```

### Validation with Custom Messages

```tsx
const { error } = useFieldValidation('password', [
  { rule: 'required', message: 'Password is required' },
  { rule: 'minLength:8', message: 'Password must be 8+ characters' },
  { rule: 'pattern:[A-Z]', message: 'Must contain uppercase letter' },
]);
```

## Context Providers

### Individual Contexts

If you need fine-grained control, use individual providers:

```tsx
import {
  DataProvider,
  ActionProvider,
  VisibilityProvider,
  ValidationProvider,
  ComponentProvider,
} from '@json-render/react';

function App() {
  return (
    <DataProvider initialData={data}>
      <ActionProvider onAction={handleAction}>
        <VisibilityProvider auth={authContext}>
          <ValidationProvider catalog={catalog}>
            <ComponentProvider components={components}>
              <Renderer tree={ui} />
            </ComponentProvider>
          </ValidationProvider>
        </VisibilityProvider>
      </ActionProvider>
    </DataProvider>
  );
}
```

## Component Registry

The component registry maps element types to React components.

### Registry Type

```typescript
type ComponentRegistry = {
  [type: string]: React.ComponentType<ComponentProps<any>>;
};

interface ComponentProps<T> {
  // Props from the UI element
  ...T;

  // Injected by Renderer
  element: UIElement;           // Original element
  renderChildren: (children?: UIElement[]) => ReactNode;
  onAction: (action: ActionDefinition) => void;
}
```

### Basic Components

```tsx
const components: ComponentRegistry = {
  text: ({ text }) => <p>{text}</p>,

  button: ({ label, action, onAction }) => (
    <button onClick={() => onAction({ type: action })}>
      {label}
    </button>
  ),

  card: ({ title, children, renderChildren }) => (
    <div className="card">
      {title && <h2>{title}</h2>}
      <div className="card-body">
        {renderChildren(children)}
      </div>
    </div>
  ),
};
```

### Components with Hooks

```tsx
const components: ComponentRegistry = {
  userGreeting: ({ name }) => {
    // name can be string or { $data: "/path" }
    const resolvedName = useDataBinding(name);
    return <h1>Hello, {resolvedName}!</h1>;
  },

  counter: ({ path }) => {
    const [count, setCount] = useDataValue<number>(path, 0);
    return (
      <div>
        <span>{count}</span>
        <button onClick={() => setCount(count + 1)}>+</button>
      </div>
    );
  },

  conditionalContent: ({ rule, children, renderChildren }) => {
    const isVisible = useIsVisible(rule);
    if (!isVisible) return null;
    return <div>{renderChildren(children)}</div>;
  },
};
```

### Components with Validation

```tsx
const components: ComponentRegistry = {
  validatedInput: ({ name, label, validation }) => {
    const { value, error, validate, touched, setTouched } = useFieldValidation(
      name,
      validation || []
    );

    return (
      <div className="form-field">
        <label>{label}</label>
        <input
          value={value || ''}
          onChange={(e) => validate(e.target.value)}
          onBlur={() => setTouched(true)}
          className={touched && error ? 'error' : ''}
        />
        {touched && error && <span className="error-text">{error}</span>}
      </div>
    );
  },
};
```

## Advanced Patterns

### Lazy Component Loading

```tsx
import { lazy, Suspense } from 'react';

const ChartComponent = lazy(() => import('./ChartComponent'));
const MapComponent = lazy(() => import('./MapComponent'));

const components: ComponentRegistry = {
  chart: (props) => (
    <Suspense fallback={<div>Loading chart...</div>}>
      <ChartComponent {...props} />
    </Suspense>
  ),
  map: (props) => (
    <Suspense fallback={<div>Loading map...</div>}>
      <MapComponent {...props} />
    </Suspense>
  ),
};
```

### Component Composition

```tsx
// Base input component
function BaseInput({ name, label, type, validation, ...props }) {
  const { value, error, validate, touched, setTouched } = useFieldValidation(
    name,
    validation
  );

  return (
    <div className="input-wrapper">
      <label>{label}</label>
      <input
        type={type}
        value={value || ''}
        onChange={(e) => validate(e.target.value)}
        onBlur={() => setTouched(true)}
        {...props}
      />
      {touched && error && <span className="error">{error}</span>}
    </div>
  );
}

const components: ComponentRegistry = {
  textInput: (props) => <BaseInput type="text" {...props} />,
  emailInput: (props) => <BaseInput type="email" {...props} />,
  passwordInput: (props) => <BaseInput type="password" {...props} />,
  numberInput: (props) => <BaseInput type="number" {...props} />,
};
```

### Custom Renderer Wrapper

```tsx
function CustomRenderer({ tree }: { tree: UITree | null }) {
  const [transitions, setTransitions] = useState(false);

  return (
    <motion.div
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      transition={{ duration: 0.3 }}
    >
      <Renderer
        tree={tree}
        fallback={<Skeleton />}
        onError={(error, element) => {
          trackError('ui-render-error', {
            elementType: element.type,
            error: error.message,
          });
        }}
      />
    </motion.div>
  );
}
```

### Server Components Integration

```tsx
// app/ui/[id]/page.tsx (Server Component)
import { Suspense } from 'react';
import { UIRenderer } from './UIRenderer';

async function getUI(id: string) {
  const response = await fetch(`/api/ui/${id}`);
  return response.json();
}

export default async function UIPage({ params }: { params: { id: string } }) {
  const ui = await getUI(params.id);

  return (
    <Suspense fallback={<Loading />}>
      <UIRenderer initialUI={ui} />
    </Suspense>
  );
}

// UIRenderer.tsx (Client Component)
'use client';

import { JSONUIProvider, Renderer } from '@json-render/react';

export function UIRenderer({ initialUI }: { initialUI: UITree }) {
  return (
    <JSONUIProvider components={components} catalog={catalog}>
      <Renderer tree={initialUI} />
    </JSONUIProvider>
  );
}
```

## Related Documentation

- [json-render Overview](./json-render.md) - Main documentation
- [Catalog System Reference](./json-render-catalog.md) - Catalog API details
- [Streaming Protocol Reference](./json-render-streaming.md) - JSONL protocol details
