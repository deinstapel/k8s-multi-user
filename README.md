# Multi-User Kubernetes

One of the first problems we ran into when migrating our workloads to a common, shared kubernetes cluster was to create a sane authentication and authorization model. While K8S got you covered on both topics, 'doing it right' will consume many resources we don't have at the moment.

Therefore, we needed a smaller solution which fits our requirements.

## Design Goals

- Primary goal was to have seperate namespaces for each project and for each user.
- A user should only have access to its namespaces
- It should be possible to 'share' the administration for certain namespaces between multiple users
- There should be users which have access to cluster-system namespaces such as kube-system
- It must run purely within the cluster, so no fancy external authentication providers are allowed.
- Users must be able to create new private namespaces.

## Concept

After some fiddling around, we came up with the following concept:

- Create one ServiceAccount for each user
- Create one RoleBinding for each namespace a user has access to
    - After some analysis, we came up with a good convention:
    - If a namespace name starts with a valid user name, it is considered as a 'private' namespace and the user is granted automatically
    - Privileges to other namespaces must be granted explicitly
- Generate a `kubeconfig` for each user bound to its ServiceAccount
- A user can create new 'private' namespaces (i.e. prefixed with its username)

## Implementation

After the concept was clear, we started fiddling around with specific resources and quickly came up with a nice helm chart which sets up ServiceAccounts and RoleBindings for all statically granted privileges.

The configuration looks like this:

```yaml=
users:
  - name: userA
    roles:
    - admin
  - name: userB
    roles:
    - admin
    - shared-project
  - name: userC
    roles:
    - shared-project
  - name: userD

  roles:
  - name: admin
    namespaces:
    - kube-system
    - rook-ceph-system
    - cert-manager
    - default
    - ingress
    - kube-public
  - name: shared-project
    namespaces:
    - shared-project-namespace
```

The configuration above will create:

- 4 Service accounts, one per user
- 14 RoleBindings
    - RoleBindings with ClusterRole=admin in the referenced namespace per user

So when we look back at our defined requirements, this meets quite a few already:

- Multiple users
- No external auth providers
- User-private Namespaces
- Shared Namespaces
- Cluster administration

Still missing:

- Users should be able to create new private namespaces
- Permissions on newly created private namespaces are automatically granted.
- Users should be able to use helm and should not be able to impersonate as cluster admin.

## Getting the missing parts together

When we thought about having dynamic namespaces for users, we initially thought it would be possible to grant a Cluster Role to a set of Namespaces by using wildcards. After this turned out to be impossible, we needed another solution.

We started creating a little daemon that monitors for namespace events and whenever a namespace is created, it checks for the existing users and when one user matches, it grants the permissions on this namespace by creating a Role Binding for ClusterRole admin within this namespace.

We also allow creating new namespaces for every user. Except cluster-admins, every user should be able to create namespaces, which are prefixed by their own name, e.g. `martin` should only be able to create namespaces, which are called `martin-*`. This allows seperation of concerns for every user but allows every user to create new services without an administator interaction.

This is realized with an admission webhook, which is called by our Kubernetes API Server to verify the request. If there is a request from an service account which we manage we check, if the namespace name is prefixed by the username and based on this outcome we decide if the API Server is allowed to create the namespace. If there is a request which is not from one of our managed service accounts we just allow it.

We also wanted to create a possibiliy to use helm with the permissions, which are associated with your account. If you use `helm` with the default configuration, the `tiller` pod residents in `kube-system` and has role `cluster-admin`. Anyone can use helm to deploy to any namespace, which is not intended behaviour. 

We went with a solution without `tiller` on the cluster. Right now, every user creates its own `tiller` instance, using [helm-tiller](https://github.com/rimusz/helm-tiller), on their local machine, which connects to the cluster directly. Helm will use the local `tiller` instance instead of a `tiller` instance on the cluster. 

`helm-tiller` needs to save the configuration somewhere, similar to an `tiller` in the cluster. `helm-tiller` uses a secret within a specified namespace for this job. We went with a cheap solution and create the `$USER-tiller` namespace to store secrets. This is created on the fly when using `helm` the first time. 


